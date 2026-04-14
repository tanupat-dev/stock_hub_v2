# frozen_string_literal: true

module Oauth
  class TiktokController < ApplicationController
    def start
      if params[:shop_id].present?
        shop = Shop.find(params[:shop_id])

        unless shop.channel == "tiktok"
          return render plain: "shop is not tiktok", status: :unprocessable_entity
        end

        app = tiktok_app_for_shop!(shop)
        state = SecureRandom.hex(16)

        cookies.signed[:tiktok_oauth_state] = {
          value: {
            state: state,
            shop_id: shop.id,
            tiktok_app_id: app.id
          },
          expires: 10.minutes.from_now,
          httponly: true,
          same_site: :lax
        }

        return redirect_to authorization_url(app, state), allow_other_host: true
      end

      if params[:app].present?
        app = TiktokApp.find_by(code: params[:app].to_s, active: true)
        return render plain: "Invalid app", status: :unprocessable_entity if app.nil?

        state = SecureRandom.hex(16)

        cookies.signed[:tiktok_oauth_state] = {
          value: {
            state: state,
            tiktok_app_id: app.id
          },
          expires: 10.minutes.from_now,
          httponly: true,
          same_site: :lax
        }

        return redirect_to authorization_url(app, state), allow_other_host: true
      end

      render plain: "missing shop_id", status: :unprocessable_entity
    end

    def callback
      code  = params[:code]
      state = params[:state]
      error = params[:error]

      payload = cookies.signed[:tiktok_oauth_state]
      cookies.delete(:tiktok_oauth_state)

      if payload.is_a?(Hash)
        expected_state = payload["state"] || payload[:state]
        tiktok_app_id  = payload["tiktok_app_id"] || payload[:tiktok_app_id]
        shop_id        = payload["shop_id"] || payload[:shop_id]
      else
        expected_state = nil
        tiktok_app_id  = nil
        shop_id        = nil
      end

      if expected_state.blank? || state.blank? || expected_state != state || tiktok_app_id.blank?
        Rails.logger.warn(
          {
            event: "tiktok.oauth.invalid_state",
            expected: expected_state,
            got: state,
            tiktok_app_id: tiktok_app_id,
            shop_id: shop_id,
            cookie_present: payload.present?
          }.to_json
        )
        return render plain: "Invalid state", status: :unprocessable_entity
      end

      app = TiktokApp.find_by(id: tiktok_app_id)
      unless app&.active?
        Rails.logger.warn(
          { event: "tiktok.oauth.app_not_found_or_inactive", tiktok_app_id: tiktok_app_id, shop_id: shop_id }.to_json
        )
        return render plain: "Invalid app", status: :unprocessable_entity
      end

      shop = Shop.find_by(id: shop_id) if shop_id.present?

      if shop.present? && shop.channel != "tiktok"
        Rails.logger.warn(
          { event: "tiktok.oauth.invalid_shop_channel", shop_id: shop.id, channel: shop.channel }.to_json
        )
        return render plain: "Invalid shop", status: :unprocessable_entity
      end

      if code.blank? || code == "null" || error.present?
        Rails.logger.warn(
          {
            event: "tiktok.oauth.denied",
            code: code,
            error: error,
            tiktok_app_id: app.id,
            shop_id: shop&.id
          }.to_json
        )
        return render plain: "Authorization denied", status: :unauthorized
      end

      token = Marketplace::Tiktok::Oauth.exchange_auth_code!(auth_code: code, tiktok_app: app)

      cred = TiktokCredential.find_or_initialize_by(
        tiktok_app_id: app.id,
        open_id: token.fetch(:open_id)
      )

      cred.assign_attributes(
        user_type: token[:user_type],
        seller_name: token[:seller_name],
        seller_base_region: token[:seller_base_region],
        access_token: token[:access_token],
        access_token_expires_at: token[:access_token_expires_at],
        refresh_token: token[:refresh_token],
        refresh_token_expires_at: token[:refresh_token_expires_at],
        granted_scopes: token[:granted_scopes] || [],
        active: true,
        last_error: nil
      )
      cred.save!

      if shop.present?
        updates = {}
        updates[:tiktok_app] = app if shop.tiktok_app_id != app.id
        updates[:tiktok_credential] = cred if shop.tiktok_credential_id != cred.id
        shop.update!(updates) if updates.any?
      end

      Marketplace::Tiktok::AuthorizedShops.sync!(credential: cred)

      render plain: "TikTok authorized OK (app=#{app.code})", status: :ok
    rescue => e
      Rails.logger.error(
        {
          event: "tiktok.oauth.callback.fail",
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )
      render plain: "Oauth failed", status: :internal_server_error
    end

    private

    def tiktok_app_for_shop!(shop)
      app = shop.tiktok_app || shop.tiktok_credential&.tiktok_app
      raise "shop #{shop.id} missing tiktok_app" if app.nil?
      raise "tiktok_app #{app.code} is inactive" unless app.active?
      app
    end

    def authorization_url(app, state)
      base =
        if app.auth_region.to_s.upcase == "US"
          "https://services.tiktokshops.us/open/authorize"
        else
          "https://services.tiktokshop.com/open/authorize"
        end

      "#{base}?service_id=#{app.service_id}&state=#{state}"
    end
  end
end
