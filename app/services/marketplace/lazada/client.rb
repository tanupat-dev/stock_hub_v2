# app/services/marketplace/lazada/client.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "openssl"
require "uri"
require "cgi"

module Marketplace
  module Lazada
    class Client
      DEFAULT_HOST = "https://api.lazada.co.th"
      DEFAULT_PARTNER_ID = "stockhub-v2"

      def initialize(credential:, host: DEFAULT_HOST, app_key: nil, app_secret: nil, partner_id: DEFAULT_PARTNER_ID)
        raise ArgumentError, "credential required" if credential.nil?
        raise ArgumentError, "credential missing lazada_app" if credential.lazada_app.nil?

        @credential = credential
        @app = credential.lazada_app
        @host = host || @app.api_host
        @app_key = app_key || @app.app_key
        @app_secret = app_secret || @app.app_secret
        @partner_id = partner_id

        refresh_access_token_if_needed!
        @access_token = @credential.access_token.to_s

        raise ArgumentError, "missing lazada app_key" if @app_key.blank?
        raise ArgumentError, "missing lazada app_secret" if @app_secret.blank?
        raise ArgumentError, "missing lazada access_token" if @access_token.blank?
      end

      def get(api_name, params: {})
        request(:get, api_name, params)
      end

      def post(api_name, params: {})
        request(:post, api_name, params)
      end

      private

      def refresh_access_token_if_needed!
        return unless @credential.respond_to?(:access_token_expired?)
        return unless @credential.access_token_expired?

        Marketplace::Lazada::Auth::RefreshToken.call!(credential: @credential)
        @credential.reload
      end

      def request(method, api_name, api_params)
        api_params = stringify_hash(api_params)

        timestamp = (Time.current.to_f * 1000).to_i.to_s

        sys_params = {
          "app_key" => @app_key.to_s,
          "partner_id" => @partner_id.to_s,
          "timestamp" => timestamp,
          "sign_method" => "sha256",
          "access_token" => @access_token
        }

        request_path = api_name.to_s
        sign_path = sign_path_for(request_path)

        sign = sign_request(sign_path, sys_params, api_params)

        query_params = sys_params.merge("sign" => sign)
        query_params = query_params.merge(api_params) if method == :get

        uri = URI.join(@host, request_path)
        uri.query = URI.encode_www_form(query_params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30

        req =
          case method
          when :get
            Net::HTTP::Get.new(uri.request_uri)
          when :post
            Net::HTTP::Post.new(uri.request_uri)
          else
            raise ArgumentError, "unsupported method #{method}"
          end

        req.set_form_data(api_params) if method == :post

        res = http.request(req)
        body_text = safe_text(res.body)

        Rails.logger.info(
          {
            event: "lazada.client.http",
            lazada_app_code: @app.code,
            method: method,
            request_path: request_path,
            sign_path: sign_path,
            url: uri.to_s,
            status: res.code.to_i,
            body_preview: safe_preview(body_text)
          }.to_json
        )

        parsed =
          begin
            JSON.parse(body_text)
          rescue JSON::ParserError => e
            raise "Lazada API invalid JSON status=#{res.code}: #{e.message}"
          end

        if parsed["code"].to_s == "0"
          return parsed["data"] if parsed.key?("data")
          return parsed["result"] if parsed.key?("result")
          return parsed
        end

        code = parsed["code"].to_s
        message = parsed["message"].to_s
        request_id = parsed["request_id"].to_s

        error_message =
          "Lazada API error code=#{code} message=#{message} request_id=#{request_id}"

        case code
        when "901", "E901", "ApiCallLimit"
          raise Marketplace::Lazada::Errors::RateLimitedError, error_message
        when "ServiceTimeout", "6", "E006", "1000", "513"
          raise Marketplace::Lazada::Errors::TransientError, error_message
        else
          raise Marketplace::Lazada::Errors::BusinessError, error_message
        end
      end

      def sign_path_for(request_path)
        path = request_path.to_s
        path.start_with?("/rest/") ? path.sub("/rest", "") : path
      end

      def sign_request(api_name, sys_params, api_params)
        sorted = sys_params.merge(api_params).sort_by { |k, _| k.to_s }

        sign_str = +"#{api_name}"
        sorted.each do |k, v|
          sign_str << k.to_s
          sign_str << v.to_s
        end

        OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new("sha256"),
          @app_secret,
          sign_str
        ).upcase
      end

      def safe_text(value)
        str = value.to_s.dup
        str.force_encoding(Encoding::UTF_8)

        if str.valid_encoding?
          str
        else
          str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
        end
      end

      def safe_preview(value, limit = 500)
        safe_text(value)[0, limit]
      end

      def stringify_hash(hash)
        (hash || {}).each_with_object({}) do |(k, v), out|
          out[k.to_s] = v
        end
      end
    end
  end
end
