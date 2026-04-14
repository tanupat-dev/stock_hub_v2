# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Marketplace
  module Tiktok
    class Oauth
      TOKEN_HOST = "https://auth.tiktok-shops.com"
      Errors = Marketplace::Tiktok::Errors

      def self.exchange_auth_code!(auth_code:, tiktok_app:)
        new(tiktok_app: tiktok_app).exchange_auth_code!(auth_code: auth_code)
      end

      def self.refresh!(refresh_token:, tiktok_app:)
        new(tiktok_app: tiktok_app).refresh!(refresh_token: refresh_token)
      end

      def initialize(tiktok_app:)
        @tiktok_app = tiktok_app
        raise ArgumentError, "tiktok_app required" if @tiktok_app.nil?
        raise ArgumentError, "tiktok_app.app_key missing" if @tiktok_app.app_key.blank?
        raise ArgumentError, "tiktok_app.app_secret missing" if @tiktok_app.app_secret.blank?
      end

      def exchange_auth_code!(auth_code:)
        uri = URI("#{TOKEN_HOST}/api/v2/token/get")
        uri.query = URI.encode_www_form(
          app_key: @tiktok_app.app_key,
          app_secret: @tiktok_app.app_secret,
          auth_code: auth_code,
          grant_type: "authorized_code"
        )

        res = Net::HTTP.get_response(uri)
        body = safe_json(res.body)

        raise http_error(res, body) unless res.is_a?(Net::HTTPSuccess)
        raise api_error(body) unless body["code"].to_i == 0

        normalize_token_payload(body.fetch("data"))
      rescue Errors::Error
        raise
      rescue => e
        # network/parse/etc => transient
        raise Errors::TransientError.new(e.message, code: nil, request_id: nil)
      end

      def refresh!(refresh_token:)
        uri = URI("#{TOKEN_HOST}/api/v2/token/refresh")
        uri.query = URI.encode_www_form(
          app_key: @tiktok_app.app_key,
          app_secret: @tiktok_app.app_secret,
          refresh_token: refresh_token,
          grant_type: "refresh_token"
        )

        res = Net::HTTP.get_response(uri)
        body = safe_json(res.body)

        raise http_error(res, body) unless res.is_a?(Net::HTTPSuccess)
        raise api_error(body) unless body["code"].to_i == 0

        normalize_token_payload(body.fetch("data"))
      rescue Errors::Error
        raise
      rescue => e
        raise Errors::TransientError.new(e.message, code: nil, request_id: nil)
      end

      private

      def safe_json(raw)
        JSON.parse(raw)
      rescue
        { "raw" => raw }
      end

      def http_error(res, body)
        rid = body.is_a?(Hash) ? body["request_id"] : nil
        Errors::TransientError.new("HTTP #{res.code} #{res.message}", code: nil, request_id: rid)
      end

      def api_error(body)
        code = body["code"].to_i
        msg  = body["message"].to_s
        rid  = body["request_id"]

        m = "#{msg} (code=#{code}, request_id=#{rid})"
        down = msg.downcase

        # token endpoint ก็โดน rate limit ได้เหมือนกัน
        return Errors::RateLimitedError.new(m, code: code, request_id: rid) if down.include?("rate") || down.include?("too many")
        return Errors::UnauthorizedError.new(m, code: code, request_id: rid) if down.include?("unauthorized") || down.include?("invalid") || down.include?("expired")

        # อย่างอื่นถือว่า transient ไว้ก่อน (จะได้ retry ได้)
        Errors::TransientError.new(m, code: code, request_id: rid)
      end

      def normalize_token_payload(data)
        {
          access_token: data.fetch("access_token"),
          access_token_expires_at: Time.at(data.fetch("access_token_expire_in").to_i),
          refresh_token: data.fetch("refresh_token"),
          refresh_token_expires_at: Time.at(data.fetch("refresh_token_expire_in").to_i),
          open_id: data.fetch("open_id"),
          seller_name: data["seller_name"],
          seller_base_region: data["seller_base_region"],
          user_type: data["user_type"],
          granted_scopes: data["granted_scopes"] || []
        }
      end
    end
  end
end