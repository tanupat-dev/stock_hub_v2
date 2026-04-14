# app/services/marketplace/lazada/auth/refresh_token.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "openssl"
require "uri"

module Marketplace
  module Lazada
    module Auth
      class RefreshToken
        SIGN_PATH = "/auth/token/refresh"
        URL_PATH = "/rest/auth/token/refresh"

        def self.call!(credential:)
          new(credential).call!
        end

        def initialize(credential)
          raise ArgumentError, "credential required" if credential.nil?
          raise ArgumentError, "credential missing lazada_app" if credential.lazada_app.nil?

          @credential = credential
          @app = credential.lazada_app
          @app_key = @app.app_key.to_s
          @app_secret = @app.app_secret.to_s
          @api_host = @app.api_host.to_s.presence || "https://api.lazada.co.th"

          raise ArgumentError, "missing lazada app_key" if @app_key.blank?
          raise ArgumentError, "missing lazada app_secret" if @app_secret.blank?
          raise ArgumentError, "missing refresh_token" if @credential.refresh_token.blank?
        end

        def call!
          timestamp = (Time.current.to_f * 1000).to_i.to_s

          sys_params = {
            "app_key" => @app_key,
            "timestamp" => timestamp,
            "sign_method" => "sha256"
          }

          api_params = {
            "refresh_token" => @credential.refresh_token.to_s
          }

          sign = sign_request(SIGN_PATH, sys_params, api_params)

          uri = URI.join(@api_host, URL_PATH)
          uri.query = URI.encode_www_form(sys_params.merge("sign" => sign))

          req = Net::HTTP::Post.new(uri.request_uri)
          req.set_form_data(api_params)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 10
          http.read_timeout = 30

          res = http.request(req)

          body_text = safe_text(res.body)

          Rails.logger.info(
            {
              event: "lazada.auth.refresh_token.http",
              credential_id: @credential.id,
              lazada_app_code: @app.code,
              status: res.code.to_i,
              body_preview: safe_preview(body_text)
            }.to_json
          )

          parsed =
            begin
              JSON.parse(body_text)
            rescue JSON::ParserError
              raise "Lazada refresh token returned non-JSON: status=#{res.code} body=#{safe_preview(body_text)}"
            end

          unless parsed["code"].to_s == "0"
            raise(
              "Lazada refresh token error code=#{parsed["code"]} " \
              "message=#{parsed["message"]} request_id=#{parsed["request_id"]}"
            )
          end

          persist!(parsed)

          parsed
        end

        private

        def persist!(payload)
          country_info =
            Array(payload["country_user_info"]).first ||
            Array(payload["country_user_info_list"]).first ||
            {}

          now = Time.current

          @credential.update!(
            access_token: payload["access_token"],
            refresh_token: payload["refresh_token"].presence || @credential.refresh_token,
            expires_at: expires_at_from(payload["expires_in"]),
            refresh_expires_at: expires_at_from(payload["refresh_expires_in"]),
            account: payload["account"],
            account_platform: payload["account_platform"],
            country: payload["country"],
            seller_id: country_info["seller_id"]&.to_s,
            user_id: country_info["user_id"]&.to_s,
            short_code: country_info["short_code"]&.to_s,
            raw_payload: payload,
            updated_at: now
          )
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

        def expires_at_from(seconds)
          s = seconds.to_i
          return nil if s <= 0
          Time.current + s
        end

        def safe_text(value)
          value.to_s.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
        end

        def safe_preview(value, limit = 500)
          safe_text(value)[0, limit]
        end
      end
    end
  end
end
