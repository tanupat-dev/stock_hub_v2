# frozen_string_literal: true

module Shopee
  class StocksController < ApplicationController
    def export
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

      tmp_dir = Rails.root.join("tmp", "uploads", "shopee_stock_templates")
      out_dir = Rails.root.join("tmp", "exports", "shopee")
      FileUtils.mkdir_p(tmp_dir)
      FileUtils.mkdir_p(out_dir)

      template_filename = "#{Time.current.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(6)}#{ext}"
      template_path = tmp_dir.join(template_filename)

      if uploaded.respond_to?(:read)
        File.binwrite(template_path, uploaded.read)
      elsif uploaded.respond_to?(:path)
        FileUtils.cp(uploaded.path, template_path)
      else
        raise ArgumentError, "unsupported uploaded file object"
      end

      output_filename = "shopee_stock_export_shop#{shop.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx"
      output_path = out_dir.join(output_filename)

      result = ::Shopee::ExportStockExcel.call!(
        shop: shop,
        template_path: template_path.to_s,
        output_path: output_path.to_s
      )

      batch = FileBatch.find(result.fetch(:batch_id))

      if xlsx_download_request?
        unless File.exist?(output_path)
          raise "export file was not generated"
        end

        return send_file(
          output_path,
          filename: File.basename(output_path),
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          disposition: "attachment"
        )
      end

      render json: {
        ok: true,
        batch_id: batch.id,
        channel: "shopee",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        template_filename: original_filename,
        output_filename: File.basename(output_path),
        output_path: output_path.to_s,
        total_rows: result[:total_rows],
        updated_rows: result[:updated_rows],
        batch_status: batch.status,
        error_summary: batch.error_summary
      }, status: :ok
    rescue => e
      Rails.logger.error(
        {
          event: "shopee.stocks.export.fail",
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

    def xlsx_download_request?
      request.format.xlsx? ||
        request.headers["Accept"].to_s.include?(
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
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
