# frozen_string_literal: true

module Pos
  class ExchangesController < BaseController
    # POST /pos/exchanges
    def create
      shop = find_pos_shop!
      sale = PosSale.find(params.require(:pos_sale_id))

      exchange = Pos::Exchanges::CreateExchange.call!(
        shop: shop,
        pos_sale: sale,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        pos_exchange: serialize_exchange(exchange)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "sale not found" }, status: :not_found
    rescue Pos::Exchanges::CreateExchange::SaleNotCheckedOut,
           Pos::Exchanges::CreateExchange::SaleVoided,
           Pos::Exchanges::CreateExchange::ShopMismatch => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/exchanges/lookup
    def lookup
      exchange = find_exchange_for_lookup!

      render json: {
        ok: true,
        pos_exchange: serialize_exchange(exchange)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "exchange not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    end

    # GET /pos/exchanges/:id
    def show
      exchange = PosExchange.includes(:pos_sale, :pos_return, :new_pos_sale).find(params[:id])

      render json: {
        ok: true,
        pos_exchange: serialize_exchange(exchange)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "exchange not found" }, status: :not_found
    end

    # POST /pos/exchanges/:id/attach_return
    def attach_return
      exchange = PosExchange.find(params[:id])
      pos_return = PosReturn.find(params.require(:pos_return_id))

      exchange = Pos::Exchanges::AttachReturn.call!(
        pos_exchange: exchange,
        pos_return: pos_return,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        pos_exchange: serialize_exchange(exchange.reload)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue Pos::Exchanges::AttachReturn::ExchangeNotOpen,
           Pos::Exchanges::AttachReturn::ReturnSaleMismatch,
           Pos::Exchanges::AttachReturn::ShopMismatch => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/exchanges/:id/attach_new_sale
    def attach_new_sale
      exchange = PosExchange.find(params[:id])
      new_sale = PosSale.find(params.require(:new_pos_sale_id))

      exchange = Pos::Exchanges::AttachNewSale.call!(
        pos_exchange: exchange,
        new_pos_sale: new_sale,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        pos_exchange: serialize_exchange(exchange.reload)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue Pos::Exchanges::AttachNewSale::ExchangeNotOpen,
           Pos::Exchanges::AttachNewSale::ShopMismatch,
           Pos::Exchanges::AttachNewSale::SameSaleNotAllowed,
           Pos::Exchanges::AttachNewSale::SaleVoided,
           Pos::Exchanges::AttachNewSale::SaleAlreadyAttached => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /pos/exchanges/:id/complete
    def complete
      exchange = PosExchange.find(params[:id])

      exchange = Pos::Exchanges::CompleteExchange.call!(
        pos_exchange: exchange,
        idempotency_key: params.require(:idempotency_key),
        meta: { source: "pos_api" }
      )

      render json: {
        ok: true,
        pos_exchange: serialize_exchange(exchange.reload)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "exchange not found" }, status: :not_found
    rescue Pos::Exchanges::CompleteExchange::ExchangeNotOpen,
           Pos::Exchanges::CompleteExchange::MissingReturn,
           Pos::Exchanges::CompleteExchange::MissingNewSale,
           Pos::Exchanges::CompleteExchange::ReturnNotCompleted,
           Pos::Exchanges::CompleteExchange::NewSaleNotCheckedOut,
           Pos::Exchanges::CompleteExchange::ShopMismatch,
           Pos::Exchanges::CompleteExchange::SaleMismatch => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def find_pos_shop!
      Shop.find_by!(channel: "pos", active: true)
    end

    def find_exchange_for_lookup!
      scope = PosExchange.includes(:pos_sale, :pos_return, :new_pos_sale)

      if params[:id].present?
        scope.find(params[:id])
      else
        scope.find_by!(exchange_number: params.require(:exchange_number))
      end
    end

    def serialize_exchange(exchange)
      {
        id: exchange.id,
        exchange_number: exchange.exchange_number,
        status: exchange.status,
        pos_sale_id: exchange.pos_sale_id,
        pos_return_id: exchange.pos_return_id,
        new_pos_sale_id: exchange.new_pos_sale_id,
        completed_at: exchange.completed_at,
        cancelled_at: exchange.cancelled_at,
        created_at: exchange.created_at,
        original_sale: serialize_sale_summary(exchange.pos_sale),
        pos_return: serialize_return_summary(exchange.pos_return),
        new_sale: serialize_sale_summary(exchange.new_pos_sale),
        allowed_actions: {
          attach_return: exchange.open?,
          attach_new_sale: exchange.open?,
          complete: exchange.open? && exchange.pos_return&.completed? && exchange.new_pos_sale&.checked_out?
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

    def serialize_return_summary(pos_return)
      return nil unless pos_return

      {
        id: pos_return.id,
        return_number: pos_return.return_number,
        status: pos_return.status,
        completed_at: pos_return.completed_at,
        cancelled_at: pos_return.cancelled_at
      }
    end
  end
end
