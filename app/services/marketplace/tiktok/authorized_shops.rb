# frozen_string_literal: true

module Marketplace
  module Tiktok
    class AuthorizedShops
      class Error < StandardError; end
      class CredentialInactive < Error; end

      def self.fetch!(credential:)
        new(credential:).fetch!
      end

      def self.sync!(credential:)
        new(credential:).sync!
      end

      def initialize(credential:)
        @credential = credential
      end

      def fetch!
        raise ArgumentError, "credential required" if @credential.nil?
        raise CredentialInactive, "credential inactive" if @credential.active == false

        client = Marketplace::Tiktok::Client.new(credential: @credential)
        data = client.get("/authorization/202309/shops")
        shops = Array(data["shops"])

        {
          count: shops.size,
          shops: shops
        }
      end

      def sync!
        raise ArgumentError, "credential required" if @credential.nil?
        raise CredentialInactive, "credential inactive" if @credential.active == false

        result = fetch!
        shops  = result[:shops]

        now = Time.current

        rows = shops.map { |h| build_shop_row(h, now:) }.compact
        shop_codes = rows.map { |r| r[:shop_code] }.uniq

        Shop.transaction do
          if rows.any?
            Shop.upsert_all(
              rows,
              unique_by: :index_shops_on_channel_and_shop_code,
              record_timestamps: false,
              update_only: %i[
                name external_shop_id shop_cipher
                region seller_type
                tiktok_app_id tiktok_credential_id
                active updated_at
              ]
            )
          end

          if shop_codes.any?
            Shop.where(channel: "tiktok", tiktok_credential_id: @credential.id)
                .where.not(shop_code: shop_codes)
                .update_all(active: false, updated_at: now)
          else
            Rails.logger.warn(
              {
                event: "tiktok.authorized_shops.sync.empty",
                credential_id: @credential.id
              }.to_json
            )
          end
        end

        Rails.logger.info(
          {
            event: "tiktok.authorized_shops.sync.done",
            credential_id: @credential.id,
            open_id: @credential.open_id,
            count: rows.size,
            shop_codes: shop_codes
          }.to_json
        )

        {
          ok: true,
          count: rows.size,
          shop_codes: shop_codes
        }
      rescue => e
        Rails.logger.error(
          {
            event: "tiktok.authorized_shops.sync.fail",
            credential_id: @credential&.id,
            open_id: @credential&.open_id,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
        raise
      end

      private

      def build_shop_row(h, now:)
        shop_code = h["code"].presence
        return nil if shop_code.blank?

        {
          channel: "tiktok",
          shop_code: shop_code,
          name: h["name"],
          external_shop_id: h["id"],
          shop_cipher: h["cipher"],
          region: h["region"],
          seller_type: h["seller_type"],
          tiktok_app_id: @credential.tiktok_app_id,
          tiktok_credential_id: @credential.id,
          active: true,
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
