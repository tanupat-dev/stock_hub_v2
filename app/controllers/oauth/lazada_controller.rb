# app/controllers/oauth/lazada_controller.rb
# frozen_string_literal: true

require "uri"
require "net/http"
require "json"
require "openssl"

module Oauth
  class LazadaController < ApplicationController
    AUTHORIZE_PATH = "/oauth/authorize"
    TOKEN_CREATE_SIGN_PATH = "/auth/token/create"
    TOKEN_CREATE_URL_PATH = "/rest/auth/token/create"

    def start
      shop = Shop.find(params[:shop_id])

      unless shop.channel == "lazada"
        return render plain: "shop is not lazada", status: :unprocessable_entity
      end

      app = lazada_app_for_shop!(shop)

      auth_url = build_authorize_url(
        app: app,
        redirect_uri: lazada_callback_url(app),
        state: signed_state_for(shop, app)
      )

      redirect_to auth_url, allow_other_host: true
    end

    def callback
      code = params[:code].to_s
      state = params[:state].to_s

      return render plain: "missing code", status: :unprocessable_entity if code.blank?

      context = context_from_state(state)
      return render plain: "invalid state", status: :unprocessable_entity if context.nil?

      shop = context[:shop]
      app = context[:app]

      token_data = exchange_code_for_token(code: code, app: app)

      credential = shop.lazada_credential.presence || LazadaCredential.new
      credential.lazada_app = app

      country_info =
        Array(token_data["country_user_info"]).first ||
        Array(token_data["country_user_info_list"]).first ||
        {}

      credential.access_token = token_data.fetch("access_token")
      credential.refresh_token = token_data["refresh_token"]
      credential.expires_at = expires_at_from(token_data["expires_in"])
      credential.refresh_expires_at = expires_at_from(token_data["refresh_expires_in"])
      credential.account = token_data["account"]
      credential.account_platform = token_data["account_platform"]
      credential.country = token_data["country"]
      credential.seller_id = country_info["seller_id"]&.to_s
      credential.user_id = country_info["user_id"]&.to_s
      credential.short_code = country_info["short_code"]&.to_s
      credential.raw_payload = token_data
      credential.save!

      updates = {}
      updates[:lazada_credential] = credential if shop.lazada_credential_id != credential.id
      updates[:lazada_app] = app if shop.lazada_app_id != app.id
      shop.update!(updates) if updates.any?

      render json: {
        ok: true,
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        lazada_app_code: app.code,
        seller_id: credential.seller_id,
        short_code: credential.short_code,
        has_access_token: credential.access_token.present?,
        expires_at: credential.expires_at,
        refresh_expires_at: credential.refresh_expires_at,
        callback_url_used: lazada_callback_url(app)
      }
    rescue => e
      Rails.logger.error(
        {
          event: "oauth.lazada.callback.fail",
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      render json: {
        ok: false,
        error: e.class.name,
        message: e.message
      }, status: :unprocessable_entity
    end

    private

    def lazada_app_for_shop!(shop)
      app = shop.lazada_app || shop.lazada_credential&.lazada_app
      raise "shop #{shop.id} missing lazada_app" if app.nil?
      raise "lazada_app #{app.code} is inactive" unless app.active?
      app
    end

    def lazada_callback_url(app)
      app.callback_url.to_s.presence ||
        oauth_lazada_callback_url(
          host: request.host,
          protocol: request.protocol,
          port: request.optional_port
        )
    end

    def signed_state_for(shop, app)
      verifier.generate(
        {
          shop_id: shop.id,
          lazada_app_id: app.id,
          ts: Time.current.to_i
        }.to_json
      )
    end

    def context_from_state(state)
      payload = verifier.verify(state)
      parsed = JSON.parse(payload)

      shop = Shop.find_by(id: parsed["shop_id"])
      return nil if shop.nil?

      app =
        if parsed["lazada_app_id"].present?
          LazadaApp.find_by(id: parsed["lazada_app_id"])
        else
          shop.lazada_app || shop.lazada_credential&.lazada_app
        end

      return nil if app.nil?

      { shop: shop, app: app }
    rescue
      nil
    end

    def verifier
      secret = Rails.application.secret_key_base
      ActiveSupport::MessageVerifier.new(secret, digest: "SHA256", serializer: JSON)
    end

    def build_authorize_url(app:, redirect_uri:, state:)
      uri = URI.join(app.auth_host, AUTHORIZE_PATH)
      uri.query = URI.encode_www_form(
        response_type: "code",
        force_auth: "true",
        client_id: app.app_key,
        redirect_uri: redirect_uri,
        state: state
      )
      uri.to_s
    end

    def exchange_code_for_token(code:, app:)
      timestamp = (Time.current.to_f * 1000).to_i.to_s

      sys_params = {
        "app_key" => app.app_key.to_s,
        "timestamp" => timestamp,
        "sign_method" => "sha256"
      }

      api_params = {
        "code" => code,
        "redirect_uri" => lazada_callback_url(app)
      }

      sign = sign_request(TOKEN_CREATE_SIGN_PATH, sys_params, api_params, app.app_secret.to_s)

      uri = URI.join(app.api_host, TOKEN_CREATE_URL_PATH)
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
          event: "oauth.lazada.token_exchange.http",
          lazada_app_code: app.code,
          status: res.code.to_i,
          body_preview: safe_preview(body_text)
        }.to_json
      )

      parsed =
        begin
          JSON.parse(body_text)
        rescue JSON::ParserError
          raise "Lazada token exchange returned non-JSON: status=#{res.code} body=#{safe_preview(body_text)}"
        end

      if parsed["code"].to_s == "0"
        parsed["data"].presence || parsed
      else
        raise(
          "Lazada token exchange error code=#{parsed["code"]} " \
          "message=#{parsed["message"]} request_id=#{parsed["request_id"]}"
        )
      end
    end

    def sign_request(api_name, sys_params, api_params, app_secret)
      sorted = sys_params.merge(api_params).sort_by { |k, _| k.to_s }

      sign_str = +"#{api_name}"
      sorted.each do |k, v|
        sign_str << k.to_s
        sign_str << v.to_s
      end

      OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new("sha256"),
        app_secret,
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
