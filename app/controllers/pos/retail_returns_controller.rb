# frozen_string_literal: true

module Pos
  class RetailReturnsController < BaseController
    # POST /pos/retail_returns
    def create
      shop = find_pos_shop!
      sale = PosSale.find(params.require(:pos_sale_id))

      pos_return = Pos::Returns::CreateReturn.call!(
        shop: shop,
        pos_sale: sale,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        pos_return: serialize_return(pos_return, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "sale not found" }, status: :not_found
    rescue Pos::Returns::CreateReturn::SaleNotCheckedOut,
           Pos::Returns::CreateReturn::SaleVoided,
           Pos::Returns::CreateReturn::ShopMismatch => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/retail_returns/lookup
    def lookup
      pos_return = find_pos_return_for_lookup!

      render json: {
        ok: true,
        pos_return: serialize_return(pos_return, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "return not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    end

    # GET /pos/retail_returns/:id
    def show
      pos_return = PosReturn.includes(:pos_sale, pos_return_lines: [ :sku, :pos_sale_line ]).find(params[:id])

      render json: {
        ok: true,
        pos_return: serialize_return(pos_return, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "return not found" }, status: :not_found
    end

    # POST /pos/retail_returns/:id/add_line
    def add_line
      pos_return = PosReturn.find(params[:id])
      pos_sale_line = PosSaleLine.find(params.require(:pos_sale_line_id))

      line = Pos::Returns::AddLine.call!(
        pos_return: pos_return,
        pos_sale_line: pos_sale_line,
        quantity: params.require(:quantity),
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        line: serialize_return_line(line),
        pos_return: serialize_return(pos_return.reload, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue Pos::Returns::AddLine::ReturnNotOpen,
           Pos::Returns::AddLine::SaleLineMismatch,
           Pos::Returns::AddLine::ReturnExceedsSold,
           Pos::Returns::AddLine::SaleNotCheckedOut,
           Pos::Returns::AddLine::SaleVoided,
           Pos::Returns::AddLine::SaleLineNotActive => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/retail_returns/:id/complete
    def complete
      pos_return = PosReturn.find(params[:id])

      pos_return = Pos::Returns::CompleteReturn.call!(
        pos_return: pos_return,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        pos_return: serialize_return(pos_return.reload, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "return not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue Pos::Returns::CompleteReturn::ReturnNotOpen,
           Pos::Returns::CompleteReturn::EmptyReturn => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def find_pos_shop!
      Shop.find_by!(channel: "pos", active: true)
    end

    def find_pos_return_for_lookup!
      scope = PosReturn.includes(:pos_sale, pos_return_lines: [ :sku, :pos_sale_line ])

      if params[:id].present?
        scope.find(params[:id])
      else
        scope.find_by!(return_number: params.require(:return_number))
      end
    end

    def serialize_return(pos_return, include_lines:)
      lines = include_lines ? pos_return.pos_return_lines.order(:id).to_a : []

      data = {
        id: pos_return.id,
        return_number: pos_return.return_number,
        status: pos_return.status,
        pos_sale_id: pos_return.pos_sale_id,
        completed_at: pos_return.completed_at,
        cancelled_at: pos_return.cancelled_at,
        created_at: pos_return.created_at,
        sale: serialize_sale_summary(pos_return.pos_sale),
        summary: {
          line_count: lines.size,
          total_qty: lines.sum { |line| line.quantity.to_i }
        },
        allowed_actions: {
          add_line: pos_return.open?,
          complete: pos_return.open? && lines.any?
        }
      }

      if include_lines
        data[:lines] = lines.map { |line| serialize_return_line(line) }
      end

      data
    end

    def serialize_return_line(line)
      sale_line = line.pos_sale_line

      {
        id: line.id,
        pos_sale_line_id: line.pos_sale_line_id,
        sku_id: line.sku_id,
        sku_code: line.sku_code_snapshot,
        barcode: line.barcode_snapshot,
        quantity: line.quantity,
        sale_line: {
          id: sale_line.id,
          status: sale_line.status,
          sold_qty: sale_line.quantity,
          returned_qty: sale_line.returned_qty,
          returnable_qty: sale_line.returnable_qty
        }
      }
    end

    def serialize_sale_summary(sale)
      return nil unless sale

      {
        id: sale.id,
        sale_number: sale.sale_number,
        status: sale.status,
        item_count: sale.item_count,
        checked_out_at: sale.checked_out_at,
        voided_at: sale.voided_at
      }
    end
  end
end
