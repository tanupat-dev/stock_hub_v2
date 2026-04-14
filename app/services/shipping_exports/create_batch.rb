# frozen_string_literal: true

require "securerandom"
require "fileutils"

module ShippingExports
  class CreateBatch
    DEFAULT_TEMPLATE_NAME = "shipping_control_v1"

    def self.call!(filters:, export_key: nil, export_date: Date.current)
      new(filters:, export_key:, export_date:).call!
    end

    def initialize(filters:, export_key:, export_date:)
      @filters = (filters || {}).to_h.symbolize_keys
      @export_key = export_key.presence || SecureRandom.uuid
      @export_date = export_date
    end

    def call!
      existing = ShippingExportBatch.find_by(export_key: export_key)
      return existing if existing.present?

      batch = ShippingExportBatch.create!(
        export_key: export_key,
        status: "building",
        template_name: DEFAULT_TEMPLATE_NAME,
        filters_snapshot: filters,
        requested_at: Time.current
      )

      orders = ShippingExports::OrderScope.call(filters: filters).to_a
      rows = ShippingExports::RowBuilder.call(orders: orders, export_date: export_date)

      output_path = build_output_path(batch)

      ActiveRecord::Base.transaction do
        orders.each do |order|
          ShippingExportBatchItem.create!(
            shipping_export_batch: batch,
            order: order,
            channel: order.channel,
            shop_id: order.shop_id,
            external_order_id: order.external_order_id,
            order_status_snapshot: order.status,
            payload_snapshot: {
              shop_code: order.shop&.shop_code,
              buyer_name: order.buyer_name,
              province: order.province
            }
          )
        end

        ShippingExports::XlsxGenerator.call(
          rows: rows,
          export_date: export_date,
          output_path: output_path
        )

        batch.update!(
          status: "completed",
          row_count: rows.size,
          file_path: output_path,
          completed_at: Time.current,
          debug_meta: {
            order_count: orders.size,
            channels: orders.group_by(&:channel).transform_values(&:size),
            shops: orders.group_by { |o| o.shop&.shop_code }.transform_values(&:size)
          }
        )

        batch.shipping_export_batch_items.update_all(exported_at: Time.current)
      end

      batch
    rescue ActiveRecord::RecordNotUnique => e
      raise e
    rescue => e
      batch&.update!(
        status: "failed",
        error_message: "#{e.class}: #{e.message}",
        failed_at: Time.current
      )
      raise
    end

    private

    attr_reader :filters, :export_key, :export_date

    def build_output_path(batch)
      dir = Rails.root.join("tmp", "exports", "shipping")
      FileUtils.mkdir_p(dir)

      filename = [
        "shipping_export",
        export_date.strftime("%Y%m%d"),
        batch.id
      ].join("_") + ".xlsx"

      dir.join(filename).to_s
    end
  end
end
