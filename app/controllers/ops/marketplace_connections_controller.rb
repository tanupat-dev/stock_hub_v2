# app/controllers/ops/marketplace_connections_controller.rb
# frozen_string_literal: true

module Ops
  class MarketplaceConnectionsController < BaseController
    def index
      @active_ops_nav = :marketplace_connections

      @tiktok_shops = normalize_shops(
        Shop.where(channel: "tiktok")
            .includes(:tiktok_app, tiktok_credential: :tiktok_app)
            .to_a
      )

      @lazada_shops = normalize_shops(
        Shop.where(channel: "lazada")
            .includes(:lazada_app, :lazada_credential)
            .to_a
      )

      @callback_urls = callback_urls_payload
    end

    def create
      channel = params.require(:channel).to_s.strip

      result =
        case channel
        when "tiktok"
          create_or_update_tiktok_connection!
        when "lazada"
          create_or_update_lazada_connection!
        else
          return render json: { ok: false, error: "unsupported channel" }, status: :bad_request
        end

      render json: result
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "ops.marketplace_connections.create.failed",
          err_class: e.class.name,
          err_message: e.message,
          channel: params[:channel]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def destroy
      shop = Shop.find(params[:id])

      if shop.orders.exists?
        return render json: { ok: false, error: "cannot delete shop with existing orders" }, status: :unprocessable_entity
      end

      shop.destroy!

      render json: { ok: true, id: shop.id }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "shop not found" }, status: :not_found
    rescue ActiveRecord::DeleteRestrictionError
      render json: { ok: false, error: "shop is still referenced and cannot be deleted" }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "ops.marketplace_connections.destroy.failed",
          err_class: e.class.name,
          err_message: e.message,
          id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def create_or_update_tiktok_connection!
      shop_name = params[:shop_name]
      external_shop_id = params.require(:shop_id)
      app_key = params.require(:app_key)
      app_secret = params.require(:app_secret)

      result = MarketplaceConnections::Tiktok::PrepareConnection.call!(
        shop_name: shop_name,
        external_shop_id: external_shop_id,
        app_key: app_key,
        app_secret: app_secret
      )

      shop = result.fetch(:shop)

      {
        ok: true,
        channel: "tiktok",
        shop: {
          id: shop.id,
          shop_code: shop.shop_code,
          name: display_shop_name(shop),
          external_shop_id: shop.external_shop_id
        },
        callback_url: callback_urls_payload[:tiktok],
        connect_url: oauth_tiktok_start_path(shop_id: shop.id)
      }
    end

    def create_or_update_lazada_connection!
      shop_name = params[:shop_name]
      seller_input = params.require(:seller_id)
      app_key = params.require(:app_key)
      app_secret = params.require(:app_secret)

      result = MarketplaceConnections::Lazada::PrepareConnection.call!(
        shop_name: shop_name,
        seller_input: seller_input,
        app_key: app_key,
        app_secret: app_secret,
        callback_url: callback_urls_payload[:lazada]
      )

      shop = result.fetch(:shop)

      {
        ok: true,
        channel: "lazada",
        shop: {
          id: shop.id,
          shop_code: shop.shop_code,
          name: display_shop_name(shop),
          external_shop_id: shop.external_shop_id
        },
        callback_url: callback_urls_payload[:lazada],
        connect_url: oauth_lazada_start_path(shop_id: shop.id)
      }
    end

    def callback_urls_payload
      {
        tiktok: oauth_tiktok_callback_url(
          host: request.host,
          protocol: request.protocol,
          port: request.optional_port
        ),
        lazada: oauth_lazada_callback_url(
          host: request.host,
          protocol: request.protocol,
          port: request.optional_port
        )
      }
    end

    def normalize_shops(shops)
      shops
        .group_by { |shop| shop_group_key(shop) }
        .values
        .map { |group| preferred_shop(group) }
        .sort_by { |shop| [ shop.channel.to_s, sort_key_for_display(shop) ] }
    end

    def preferred_shop(group)
      group.min_by do |shop|
        [
          shop.active? ? 0 : 1,
          connection_present?(shop) ? 0 : 1,
          shop.stock_sync_enabled? ? 0 : 1,
          shop.id
        ]
      end
    end

    def connection_present?(shop)
      case shop.channel.to_s
      when "tiktok"
        shop.tiktok_app_id.present? || shop.tiktok_credential_id.present?
      when "lazada"
        shop.lazada_app_id.present? || shop.lazada_credential_id.present?
      else
        false
      end
    end

    def sort_key_for_display(shop)
      case human_shop_label(shop)
      when "TikTok 1" then 1
      when "TikTok 2" then 2
      when "Lazada 1" then 1
      when "Lazada 2" then 2
      else 99
      end
    end

    def display_shop_name(shop)
      human_shop_label(shop)
    end

    def shop_group_key(shop)
      code = shop.shop_code.to_s
      name = shop.name.to_s
      external_id = shop.external_shop_id.to_s

      return "tiktok_1" if [ code, name, external_id ].any? { |v| tiktok_1_match?(v) }
      return "tiktok_2" if [ code, name, external_id ].any? { |v| tiktok_2_match?(v) }

      return "lazada_1" if [ code, name, external_id ].any? { |v| lazada_1_match?(v) }
      return "lazada_2" if [ code, name, external_id ].any? { |v| lazada_2_match?(v) }

      code.presence || "#{shop.channel}:#{shop.id}"
    end

    def human_shop_label(shop)
      return "-" if shop.nil?

      case shop_group_key(shop)
      when "tiktok_1" then "TikTok 1"
      when "tiktok_2" then "TikTok 2"
      when "lazada_1" then "Lazada 1"
      when "lazada_2" then "Lazada 2"
      else
        shop.name.presence || shop.shop_code
      end
    end

    def tiktok_1_match?(value)
      str = value.to_s.strip
      str == "7468184483922740997" ||
        str == "THLCJ4W23M" ||
        str.casecmp("Tiktok 1").zero? ||
        str.casecmp("TikTok 1").zero? ||
        str.casecmp("Thailumlongshop II").zero?
    end

    def tiktok_2_match?(value)
      str = value.to_s.strip
      str == "7469737153154172677" ||
        str == "THLCM7WX8H" ||
        str.casecmp("Tiktok 2").zero? ||
        str.casecmp("TikTok 2").zero? ||
        str.casecmp("Young smile shoes").zero?
    end

    def lazada_1_match?(value)
      str = value.to_s.strip
      str.casecmp("THJ2HAHL").zero? ||
        str.casecmp("lazada_shop_thj2hahl").zero? ||
        str.casecmp("Lazada 1").zero? ||
        str.casecmp("Thai Lumlong Shop").zero?
    end

    def lazada_2_match?(value)
      str = value.to_s.strip
      str.casecmp("TH1JHM87NL").zero? ||
        str.casecmp("lazada_shop_th1jhm87nl").zero? ||
        str.casecmp("Lazada 2").zero? ||
        str.casecmp("Thai Lumlong Shop II").zero?
    end
  end
end
