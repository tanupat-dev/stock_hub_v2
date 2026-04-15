# frozen_string_literal: true

module Pos
  class StockCountsController < BaseController
    # POST /pos/stock_counts
    def create
      shop = find_pos_shop!

      session = StockCount::CreateSession.call!(
        shop: shop,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        session: serialize_session(session)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.stock_counts.create.failed",
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # GET /pos/stock_counts/:id
    def show
      session = StockCountSession.includes(stock_count_lines: :sku).find(params[:id])

      render json: {
        ok: true,
        session: serialize_session(session, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue => e
      Rails.logger.error(
        {
          event: "pos.stock_counts.show.failed",
          err_class: e.class.name,
          err_message: e.message,
          id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/stock_counts/:id/upsert_line
    def upsert_line
      session = StockCountSession.find(params[:id])
      sku = find_sku!

      line = StockCount::UpsertLine.call!(
        session: session,
        sku: sku,
        counted_qty: params.require(:counted_qty),
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        line: serialize_line(line),
        session: serialize_session(session.reload, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue StockCount::UpsertLine::SessionNotOpen => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.stock_counts.upsert_line.failed",
          err_class: e.class.name,
          err_message: e.message,
          id: params[:id],
          sku_id: params[:sku_id],
          sku_code: params[:sku_code],
          barcode: params[:barcode]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/stock_counts/:id/confirm
    def confirm
      session = StockCountSession.find(params[:id])

      session = StockCount::ConfirmSession.call!(
        session: session,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        session: serialize_session(session.reload, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue StockCount::ConfirmSession::SessionNotOpen,
           StockCount::ConfirmSession::EmptySession => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.stock_counts.confirm.failed",
          err_class: e.class.name,
          err_message: e.message,
          id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def find_pos_shop!
      Shop.find_by!(channel: "pos", active: true)
    end

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

    def serialize_session(session, include_lines: false)
      data = {
        id: session.id,
        session_number: session.session_number,
        status: session.status,
        confirmed_at: session.confirmed_at,
        cancelled_at: session.cancelled_at
      }

      if include_lines
        data[:lines] = session.stock_count_lines.order(:id).map { |line| serialize_line(line) }
      end

      data
    end

    def serialize_line(line)
      {
        id: line.id,
        sku_id: line.sku_id,
        sku_code: line.sku_code_snapshot,
        barcode: line.barcode_snapshot,
        system_qty_snapshot: line.system_qty_snapshot,
        counted_qty: line.counted_qty,
        diff_qty: line.diff_qty,
        status: line.status
      }
    end
  end
end
