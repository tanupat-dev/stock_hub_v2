# frozen_string_literal: true

module Pos
  class StockAdjustmentsController < BaseController
    # POST /pos/stock_adjust
    #
    # modes:
    # - stock_in       => quantity required
    # - adjust_delta   => delta required
    # - adjust_set     => set_to required
    # - update_buffer  => buffer_quantity required
    #
    # lookup:
    # - barcode
    # - sku_code
    # - sku_id
    def create
      sku = find_sku!
      mode = params.require(:mode).to_s.strip
      idempotency_key = params.require(:idempotency_key).to_s
      requested_buffer_quantity = parsed_buffer_quantity

      before = sku_snapshot(sku)
      result = nil

      Sku.transaction do
        sku.lock!

        case mode
        when "update_buffer"
          if requested_buffer_quantity.nil?
            raise ActionController::ParameterMissing, "buffer_quantity is required"
          end

          if sku.buffer_quantity != requested_buffer_quantity
            sku.update!(buffer_quantity: requested_buffer_quantity)
          end

          result = :buffer_updated
        when "stock_in"
          if requested_buffer_quantity.present?
            sku.update!(buffer_quantity: requested_buffer_quantity)
          end

          result = Inventory::StockIn.call!(
            sku: sku,
            quantity: params.require(:quantity),
            idempotency_key: idempotency_key,
            meta: adjustment_meta(mode, requested_buffer_quantity)
          )
        when "adjust_delta"
          if requested_buffer_quantity.present?
            sku.update!(buffer_quantity: requested_buffer_quantity)
          end

          result = Inventory::Adjust.call!(
            sku: sku,
            delta: params.require(:delta),
            idempotency_key: idempotency_key,
            meta: adjustment_meta(mode, requested_buffer_quantity)
          )
        when "adjust_set"
          if requested_buffer_quantity.present?
            sku.update!(buffer_quantity: requested_buffer_quantity)
          end

          result = Inventory::Adjust.call!(
            sku: sku,
            set_to: params.require(:set_to),
            idempotency_key: idempotency_key,
            meta: adjustment_meta(mode, requested_buffer_quantity)
          )
        else
          return render json: {
            ok: false,
            error: "unsupported mode"
          }, status: :bad_request
        end
      end

      after = sku_snapshot(sku.reload)

      log_pos_info(
        event: "pos.stock_adjustment",
        mode: mode,
        sku_id: sku.id,
        sku: sku.code,
        barcode: sku.barcode,
        idempotency_key: idempotency_key,
        result: result,
        input: safe_input_payload(mode, requested_buffer_quantity),
        before: before,
        after: after
      )

      render json: {
        ok: true,
        mode: mode,
        result: result,
        idempotency_key: idempotency_key,
        sku: {
          id: sku.id,
          code: sku.code,
          barcode: sku.barcode,
          buffer_quantity: sku.buffer_quantity
        },
        before: before,
        after: after
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.stock_adjustments.create.failed",
          err_class: e.class.name,
          err_message: e.message,
          mode: params[:mode],
          sku_id: params[:sku_id],
          sku_code: params[:sku_code],
          barcode: params[:barcode]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def find_sku!
      if params[:sku_id].present?
        Sku.find(params[:sku_id])
      elsif params[:barcode].present?
        Sku.find_by!(barcode: params[:barcode].to_s.strip)
      elsif params[:sku_code].present?
        Sku.find_by!(code: params[:sku_code].to_s.strip)
      else
        raise ActionController::ParameterMissing, "sku_id or barcode or sku_code required"
      end
    end

    def parsed_buffer_quantity
      return nil unless params.key?(:buffer_quantity)

      value = Integer(params[:buffer_quantity])
      raise ArgumentError, "buffer_quantity must be >= 0" if value.negative?

      value
    rescue TypeError, ArgumentError
      raise ArgumentError, "buffer_quantity must be >= 0"
    end

    def adjustment_meta(mode, requested_buffer_quantity)
      {
        source: "pos_stock_adjustment",
        mode: mode,
        request_id: request.request_id,
        buffer_quantity: requested_buffer_quantity,
        raw: safe_meta_raw
      }.compact
    end

    def safe_meta_raw
      params.to_unsafe_h.slice(
        "mode",
        "sku_id",
        "sku_code",
        "barcode",
        "quantity",
        "delta",
        "set_to",
        "buffer_quantity",
        "note",
        "reason"
      )
    end

    def safe_input_payload(mode, requested_buffer_quantity)
      payload = {
        note: params[:note].to_s.presence,
        reason: params[:reason].to_s.presence,
        buffer_quantity: requested_buffer_quantity
      }

      case mode
      when "stock_in"
        payload[:quantity] = params[:quantity].to_i
      when "adjust_delta"
        payload[:delta] = params[:delta].to_i
      when "adjust_set"
        payload[:set_to] = params[:set_to].to_i
      when "update_buffer"
        # no stock payload
      end

      payload.compact
    end
  end
end
