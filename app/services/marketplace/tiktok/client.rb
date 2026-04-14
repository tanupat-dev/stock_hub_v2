# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Marketplace
  module Tiktok
    class Client
      DEFAULT_OPEN_API_HOST = "https://open-api.tiktokglobalshop.com"
      Errors = Marketplace::Tiktok::Errors

      def initialize(credential:, app_key: nil, app_secret: nil, host: nil)
        raise ArgumentError, "credential required" if credential.nil?
        @credential = credential

        app = @credential.tiktok_app
        raise ArgumentError, "credential missing tiktok_app" if app.nil?

        @app_key = app_key || app.app_key
        @app_secret = app_secret || app.app_secret
        @host = host || app.open_api_host.presence || DEFAULT_OPEN_API_HOST

        raise ArgumentError, "tiktok_app.app_key missing" if @app_key.blank?
        raise ArgumentError, "tiktok_app.app_secret missing" if @app_secret.blank?
      end

      def get(path, query: {}, content_type: "application/json")
        request(:get, path, query:, body: nil, content_type:)
      end

      # body default = nil (ไม่ส่ง "{}" มั่ว)
      def post(path, query: {}, body: nil, content_type: "application/json")
        request(:post, path, query:, body:, content_type:)
      end

      private

      # Gate debug logs (กัน log ระเบิด)
      # Usage:
      #   TIKTOK_DEBUG=1 bin/rails c
      #   TIKTOK_DEBUG=1 bin/rails server
      def debug_enabled?
        ENV["TIKTOK_DEBUG"].to_s == "1"
      end

      def request(method, path, query:, body:, content_type:)
        access_token = Marketplace::Tiktok::TokenManager.access_token_for!(credential: @credential)
        raise ArgumentError, "access_token required" if access_token.blank?

        timestamp = Time.now.to_i
        raise ArgumentError, "timestamp must be 10-digit" if timestamp < 1_000_000_000

        raw_query = (query || {})
        base_query = raw_query.merge(
          "app_key" => @app_key,
          "timestamp" => timestamp
        )

        sign = Signer.sign!(
          path: path,
          query_params: base_query,
          body: body,
          content_type: content_type,
          app_secret: @app_secret
        )

        uri = URI.join(@host, path)
        uri.query = URI.encode_www_form(base_query.merge("sign" => sign))

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 30

        req =
          case method
          when :get then Net::HTTP::Get.new(uri)
          when :post then Net::HTTP::Post.new(uri)
          else raise ArgumentError, "unsupported method=#{method}"
          end

        req["Content-Type"] = content_type
        req["x-tts-access-token"] = access_token

        if method == :post && content_type != "multipart/form-data"
          if body.is_a?(String)
            req.body = body
          elsif body.nil?
            # no body
          else
            req.body = JSON.generate(body)
          end
        end

        if debug_enabled?
          Rails.logger.info(
            {
              event: "debug.tiktok.request",
              method: method,
              path: path,
              raw_query: raw_query,
              uri: uri.to_s,
              body: req.body
            }.to_json
          )
        end

        with_retry(path:, method:, uri:) do
          res = http.request(req)

          parsed =
            begin
              JSON.parse(res.body)
            rescue
              { "raw" => res.body }
            end

          code = parsed.is_a?(Hash) ? parsed["code"] : nil
          msg  = parsed.is_a?(Hash) ? parsed["message"] : nil
          rid  = parsed.is_a?(Hash) ? parsed["request_id"] : nil

          # log 4xx เต็ม ๆ (สำคัญ)
          if res.code.to_i >= 400 && res.code.to_i < 500
            Rails.logger.error(
              {
                event: "debug.tiktok.http_4xx",
                status: res.code.to_i,
                body: res.body,
                path: path,
                uri: uri.to_s
              }.to_json
            )
          end

          # log success แบบสั้น ๆ เฉพาะตอน debug
          if debug_enabled? && res.is_a?(Net::HTTPSuccess) && code.to_i == 0
            data = parsed["data"] || {}
            Rails.logger.info(
              {
                event: "debug.tiktok.http_ok",
                status: res.code.to_i,
                path: path,
                request_id: rid,
                data_keys: data.is_a?(Hash) ? data.keys.first(30) : nil,
                next_page_token: data.is_a?(Hash) ? data["next_page_token"] : nil,
                total_count: data.is_a?(Hash) ? (data["total_count"] || data["totalCount"]) : nil,
                sample_product_ids: (data.is_a?(Hash) && data["products"].is_a?(Array)) ? data["products"].map { |p| p["id"].to_s }.first(3) : nil
              }.to_json
            )
          end

          detail = "HTTP #{res.code} #{res.message} (code=#{code}, message=#{msg}, request_id=#{rid})"

          unless res.is_a?(Net::HTTPSuccess)
            status = res.code.to_i

            if status == 429
              raise Errors::RateLimitedError.new(detail, code: code, request_id: rid)
            end

            if status >= 500
              raise Errors::TransientError.new(detail, code: code, request_id: rid)
            end

            raise Errors::Error.new(detail, code: code, request_id: rid)
          end

          raise map_error(code, msg, rid) if code.to_i != 0
          parsed.fetch("data")
        end
      end

      def with_retry(path:, method:, uri:)
        attempts = 0

        begin
          attempts += 1
          yield
        rescue Errors::RateLimitedError, Errors::TransientError => e
          log_fail(path:, method:, uri:, e:, attempts:)
          raise if attempts >= 8

          sleep(backoff_seconds(attempts))
          retry
        end
      end

      def backoff_seconds(attempts)
        base = 2**(attempts - 1)
        base + rand * base
      end

      def map_error(code, message, request_id)
        c = code.to_i
        m = "#{message} (code=#{c}, request_id=#{request_id})"
        down = m.to_s.downcase

        return Errors::TransientError.new(m, code: c, request_id: request_id) if c == 36_009_003
        return Errors::SignatureInvalidError.new(m, code: c, request_id: request_id) if down.include?("signature")
        return Errors::UnauthorizedError.new(m, code: c, request_id: request_id) if down.include?("access token") || down.include?("unauthorized")
        return Errors::RateLimitedError.new(m, code: c, request_id: request_id) if down.include?("rate") || down.include?("too many")

        Errors::Error.new(m, code: c, request_id: request_id)
      end

      def log_fail(path:, method:, uri:, e:, attempts:)
        Rails.logger.error(
          {
            event: "tiktok.open_api.fail",
            method: method,
            path: path,
            uri: uri.to_s,
            attempts: attempts,
            err_class: e.class.name,
            err_message: e.message,
            code: e.respond_to?(:code) ? e.code : nil,
            request_id: e.respond_to?(:request_id) ? e.request_id : nil,
            credential_id: @credential.id,
            tiktok_app_id: @credential.tiktok_app_id
          }.to_json
        )
      end
    end
  end
end
