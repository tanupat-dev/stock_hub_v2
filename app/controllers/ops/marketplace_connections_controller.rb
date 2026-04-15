# frozen_string_literal: true

module Ops
  class MarketplaceConnectionsController < BaseController
    def index
      @active_ops_nav = :marketplace_connections
      @tiktok_shops = Shop.where(channel: "tiktok").includes(:tiktok_app, tiktok_credential: :tiktok_app).order(:shop_code)
      @lazada_shops = Shop.where(channel: "lazada").includes(:lazada_app, :lazada_credential).order(:shop_code)
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
          name: shop.name,
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
          name: shop.name,
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
  end
end
