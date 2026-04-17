# frozen_string_literal: true

module Ops
  class ReturnsController < BaseController
    def index
      @active_ops_nav = :returns
    end

    def shops
      shops = Shop.where(channel: %w[tiktok lazada shopee])
                  .order(:channel, :shop_code)

      grouped = shops.group_by { |shop| shop_group_key(shop) }

      options = grouped.map do |group_key, group_shops|
        sample = group_shops.first

        {
          value: group_key,
          label: human_shop_label(sample),
          channel: sample.channel,
          shop_ids: group_shops.map(&:id).uniq.sort
        }
      end

      options.sort_by! do |opt|
        [
          channel_sort_key(opt[:channel]),
          label_sort_key(opt[:label])
        ]
      end

      render json: {
        ok: true,
        shops: options
      }
    rescue => e
      Rails.logger.error(
        {
          event: "ops.returns.shops.failed",
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def shop_group_key(shop)
      label = human_shop_label(shop)

      case label
      when "Lazada 1" then "lazada_1"
      when "Lazada 2" then "lazada_2"
      when "TikTok 1" then "tiktok_1"
      when "TikTok 2" then "tiktok_2"
      when "Shopee 1", "Shopee" then "shopee_1"
      else
        shop.shop_code.to_s
      end
    end

    def human_shop_label(shop)
      return "-" if shop.nil?

      code = shop.shop_code.to_s
      name = shop.name.to_s

      return "Lazada 1" if code.include?("thj2hahl")
      return "Lazada 2" if code.include?("th1jhm87nl")

      return "TikTok 1" if code.include?("7468184483922740997") || code == "THLCJ4W23M"
      return "TikTok 2" if code.include?("7469737153154172677") || code == "THLCM7WX8H"

      return "Shopee 1" if code.start_with?("shopee")

      name.presence || code
    end

    def channel_sort_key(channel)
      case channel.to_s
      when "lazada" then 1
      when "shopee" then 2
      when "tiktok" then 3
      else 9
      end
    end

    def label_sort_key(label)
      case label.to_s
      when "Lazada 1" then 1
      when "Lazada 2" then 2
      when "Shopee 1", "Shopee" then 3
      when "TikTok 1" then 4
      when "TikTok 2" then 5
      else 99
      end
    end
  end
end
