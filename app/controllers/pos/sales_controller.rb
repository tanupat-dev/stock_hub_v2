# frozen_string_literal: true

module Pos
  class SalesController < BaseController
    def create
      shop = find_pos_shop!

      sale = Pos::CreateSale.call!(
        shop: shop,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        sale: serialize_sale(sale, include_lines: true)
      }
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.create.failed",
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def index
      scope = PosSale.includes(pos_sale_lines: :sku).order(created_at: :desc, id: :desc)

      if params[:status].present?
        scope = scope.where(status: params[:status].to_s.strip)
      end

      if params[:sale_number].present?
        scope = scope.where("sale_number ILIKE ?", "%#{sanitize_sql_like(params[:sale_number].to_s.strip)}%")
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from].to_s)
        scope = scope.where("created_at >= ?", from.beginning_of_day)
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to].to_s)
        scope = scope.where("created_at <= ?", to.end_of_day)
      end

      if params[:barcode].present? || params[:sku_code].present?
        scope = scope.joins(:pos_sale_lines)

        if params[:barcode].present?
          scope = scope.where(pos_sale_lines: { barcode_snapshot: params[:barcode].to_s.strip })
        end

        if params[:sku_code].present?
          scope = scope.where(pos_sale_lines: { sku_code_snapshot: params[:sku_code].to_s.strip })
        end

        scope = scope.distinct
      end

      sales = scope.limit(normalized_sales_limit)

      render json: {
        ok: true,
        filters: current_sale_filters,
        count: sales.size,
        sales: sales.map { |sale| serialize_sale(sale, include_lines: false) }
      }
    rescue Date::Error
      render json: { ok: false, error: "invalid date" }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.index.failed",
          err_class: e.class.name,
          err_message: e.message,
          filters: current_sale_filters
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/sales/lookup
    def lookup
      sale = find_sale_for_lookup!

      render json: {
        ok: true,
        sale: serialize_sale(sale, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "sale not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.lookup.failed",
          err_class: e.class.name,
          err_message: e.message,
          params: params.to_unsafe_h.slice("id", "sale_number")
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def show
      sale = PosSale.includes(pos_sale_lines: :sku).find(params[:id])

      render json: {
        ok: true,
        sale: serialize_sale(sale, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "sale not found" }, status: :not_found
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.show.failed",
          err_class: e.class.name,
          err_message: e.message,
          id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def add_line
      sale = PosSale.find(params[:id])
      sku = find_sku!

      line = Pos::AddLine.call!(
        sale: sale,
        sku: sku,
        quantity: params.fetch(:quantity, 1),
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        line: serialize_line(line),
        sale: serialize_sale(sale.reload, include_lines: true)
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
          event: "pos.sales.add_line.failed",
          err_class: e.class.name,
          err_message: e.message,
          sale_id: params[:id],
          barcode: params[:barcode],
          sku_code: params[:sku_code]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def update_line
      line = PosSaleLine.find(params.require(:line_id))

      line = Pos::UpdateLineQuantity.call!(
        line: line,
        quantity: params.require(:quantity),
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        line: serialize_line(line),
        sale: serialize_sale(line.pos_sale.reload, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "line not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.update_line.failed",
          err_class: e.class.name,
          err_message: e.message,
          line_id: params[:line_id],
          quantity: params[:quantity]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def remove_line
      line = PosSaleLine.find(params.require(:line_id))

      line = Pos::RemoveLine.call!(
        line: line,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        line: serialize_line(line),
        sale: serialize_sale(line.pos_sale.reload, include_lines: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "line not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.remove_line.failed",
          err_class: e.class.name,
          err_message: e.message,
          line_id: params[:line_id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def checkout
      sale = PosSale.find(params[:id])

      sale = Pos::CheckoutSale.call!(
        sale: sale,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        sale: serialize_sale(sale, include_lines: true)
      }
    rescue Pos::CheckoutSale::InsufficientStock,
           Pos::CheckoutSale::EmptySale,
           Pos::CheckoutSale::SaleNotCart => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "sale not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.checkout.failed",
          err_class: e.class.name,
          err_message: e.message,
          sale_id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def void
      sale = PosSale.find(params[:id])

      sale =
        if sale.cart?
          Pos::VoidSale.new(
            sale: sale,
            idempotency_key: params.require(:idempotency_key),
            meta: { source: "pos_api", mode: "cancel_cart" }
          ).cancel_cart!
        else
          Pos::VoidSale.call!(
            sale: sale,
            idempotency_key: params.require(:idempotency_key),
            meta: { source: "pos_api", mode: "void_sale" }
          )
        end

      render json: {
        ok: true,
        sale: serialize_sale(sale, include_lines: true)
      }
    rescue Pos::VoidSale::SaleNotCheckedOut,
          Pos::VoidSale::SaleAlreadyVoided,
          Pos::VoidSale::EmptySale,
          Pos::VoidSale::SaleNotCart => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "sale not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "pos.sales.void.failed",
          err_class: e.class.name,
          err_message: e.message,
          sale_id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def find_pos_shop!
      Shop.find_by!(channel: "pos", active: true)
    end

    def find_sku!
      if params[:barcode].present?
        Sku.find_by!(barcode: params[:barcode])
      elsif params[:sku_code].present?
        Sku.find_by!(code: params[:sku_code])
      else
        raise ActionController::ParameterMissing, "barcode or sku_code required"
      end
    end

    def find_sale_for_lookup!
      scope = PosSale.includes(
        :pos_returns,
        :origin_exchanges,
        :replacement_exchanges,
        pos_sale_lines: :sku
      )

      if params[:id].present?
        scope.find(params[:id])
      else
        scope.find_by!(sale_number: params.require(:sale_number))
      end
    end

    def serialize_sale(sale, include_lines:)
      active_lines =
        if include_lines
          sale.pos_sale_lines.active_lines.order(:id).to_a
        else
          []
        end

      pos_returns =
        if sale.association(:pos_returns).loaded?
          sale.pos_returns.sort_by(&:id)
        else
          sale.pos_returns.order(:id).to_a
        end

      origin_exchanges =
        if sale.association(:origin_exchanges).loaded?
          sale.origin_exchanges.sort_by(&:id)
        else
          sale.origin_exchanges.order(:id).to_a
        end

      replacement_exchanges =
        if sale.association(:replacement_exchanges).loaded?
          sale.replacement_exchanges.sort_by(&:id)
        else
          sale.replacement_exchanges.order(:id).to_a
        end

      line_count =
        if include_lines
          active_lines.size
        else
          sale.pos_sale_lines.active_lines.count
        end

      total_qty =
        if include_lines
          active_lines.sum(&:quantity)
        else
          sale.pos_sale_lines.active_lines.sum(:quantity)
        end

      data = {
        id: sale.id,
        sale_number: sale.sale_number,
        status: sale.status,
        item_count: sale.item_count,
        checked_out_at: sale.checked_out_at,
        voided_at: sale.voided_at,
        created_at: sale.created_at,
        summary: {
          line_count: line_count,
          total_qty: total_qty,
          return_count: pos_returns.size,
          origin_exchange_count: origin_exchanges.size,
          replacement_exchange_count: replacement_exchanges.size
        },
        related_documents: {
          pos_returns: pos_returns.map { |pos_return| serialize_return_summary(pos_return) },
          origin_exchanges: origin_exchanges.map { |exchange| serialize_exchange_summary(exchange) },
          replacement_exchanges: replacement_exchanges.map { |exchange| serialize_exchange_summary(exchange) }
        },
        allowed_actions: {
          add_line: sale.cart?,
          checkout: sale.cart? && sale.item_count.to_i.positive?,
          void: sale.checked_out?,
          create_retail_return: sale.checked_out?,
          create_exchange: sale.checked_out?
        }
      }

      if include_lines
        data[:lines] = active_lines.map { |l| serialize_line(l) }
      end

      data
    end

    def serialize_line(line)
      {
        id: line.id,
        sku_id: line.sku_id,
        sku_code: line.sku_code_snapshot,
        barcode: line.barcode_snapshot,
        quantity: line.quantity,
        status: line.status,
        returned_qty: line.returned_qty,
        returnable_qty: line.returnable_qty
      }
    end

    def serialize_return_summary(pos_return)
      {
        id: pos_return.id,
        return_number: pos_return.return_number,
        status: pos_return.status,
        completed_at: pos_return.completed_at,
        cancelled_at: pos_return.cancelled_at,
        created_at: pos_return.created_at
      }
    end

    def serialize_exchange_summary(exchange)
      {
        id: exchange.id,
        exchange_number: exchange.exchange_number,
        status: exchange.status,
        pos_return_id: exchange.pos_return_id,
        new_pos_sale_id: exchange.new_pos_sale_id,
        completed_at: exchange.completed_at,
        cancelled_at: exchange.cancelled_at,
        created_at: exchange.created_at
      }
    end

    def normalized_sales_limit
      raw = params[:limit].to_i
      return 50 if raw <= 0
      return 200 if raw > 200

      raw
    end

    def current_sale_filters
      {
        status: params[:status].presence,
        sale_number: params[:sale_number].presence,
        barcode: params[:barcode].presence,
        sku_code: params[:sku_code].presence,
        date_from: params[:date_from].presence,
        date_to: params[:date_to].presence,
        limit: normalized_sales_limit
      }.compact
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end
  end
end
