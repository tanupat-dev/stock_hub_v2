# frozen_string_literal: true

module Shopee
  class OrdersController < ApplicationController
    MAX_ROWS = 10_000

    def import
      shop = find_shop!
      uploaded = params[:file]

      raise ArgumentError, "file is required" if uploaded.blank?

      original_filename =
        if uploaded.respond_to?(:original_filename)
          uploaded.original_filename.to_s
        else
          File.basename(uploaded.to_s)
        end

      ext = File.extname(original_filename).downcase
      raise ArgumentError, "only .xlsx is supported" unless ext == ".xlsx"

      temp_path = persist_temp_upload!(uploaded, ext)

      rows = ::Shopee::ImportOrders.parse_rows!(temp_path.to_s)

      if rows.size > MAX_ROWS
        return render json: {
          ok: false,
          error: "File too large",
          message: "File too large (max #{MAX_ROWS} rows)"
        }, status: :unprocessable_entity
      end

      batch = FileBatch.create!(
        channel: "shopee",
        shop: shop,
        kind: "shopee_order_import",
        status: "pending",
        source_filename: original_filename,
        total_rows: rows.size,
        meta: {
          queued_at: Time.current.iso8601,
          grouped_orders: rows.group_by { |row| row[:order_id].to_s }.size
        }
      )

      ImportShopeeOrdersJob.perform_later(batch.id, rows)

      render json: {
        ok: true,
        queued: true,
        batch_id: batch.id,
        channel: "shopee",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        filename: original_filename,
        total_rows: rows.size,
        grouped_orders: batch.meta["grouped_orders"],
        success_orders: 0,
        failed_orders: 0,
        success_rows: 0,
        failed_rows: 0,
        unknown_statuses: {},
        batch_status: batch.status,
        error_summary: nil
      }, status: :accepted
    rescue => e
      Rails.logger.error(
        {
          event: "shopee.orders.import.fail",
          err_class: e.class.name,
          err_message: e.message,
          shop_id: params[:shop_id]
        }.to_json
      )

      render json: {
        ok: false,
        error: e.class.name,
        message: e.message
      }, status: :unprocessable_entity
    ensure
      FileUtils.rm_f(temp_path) if defined?(temp_path) && temp_path.present?
    end

    private

    def persist_temp_upload!(uploaded, ext)
      tmp_dir = Rails.root.join("tmp", "uploads", "shopee_orders")
      FileUtils.mkdir_p(tmp_dir)

      temp_filename = "#{Time.current.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(6)}#{ext}"
      temp_path = tmp_dir.join(temp_filename)

      if uploaded.respond_to?(:read)
        File.binwrite(temp_path, uploaded.read)
      elsif uploaded.respond_to?(:path)
        FileUtils.cp(uploaded.path, temp_path)
      else
        raise ArgumentError, "unsupported uploaded file object"
      end

      temp_path
    end

    def find_shop!
      shop =
        if params[:shop_id].present?
          Shop.find(params[:shop_id])
        else
          Shop.find_by(channel: "shopee")
        end

      raise ActiveRecord::RecordNotFound, "Shopee shop not found" if shop.nil?
      raise ArgumentError, "shop #{shop.id} is not shopee" unless shop.channel == "shopee"

      shop
    end
  end
end
