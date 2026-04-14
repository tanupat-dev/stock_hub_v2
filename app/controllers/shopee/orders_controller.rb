# frozen_string_literal: true

module Shopee
  class OrdersController < ApplicationController
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

      result = ::Shopee::ImportOrders.call!(
        shop: shop,
        filepath: temp_path.to_s,
        source_filename: original_filename
      )

      batch = FileBatch.find(result.fetch(:batch_id))

      render json: {
        ok: result[:ok],
        batch_id: batch.id,
        channel: "shopee",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        filename: original_filename,
        total_rows: result[:total_rows],
        grouped_orders: result[:grouped_orders],
        success_orders: result[:success_orders],
        failed_orders: result[:failed_orders],
        success_rows: result[:success_rows],
        failed_rows: result[:failed_rows],
        unknown_statuses: result[:unknown_statuses],
        batch_status: batch.status,
        error_summary: batch.error_summary
      }, status: :ok
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
    end

    private

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
