# frozen_string_literal: true

module Pos
  class ScansController < BaseController
    def create
      barcode = params[:barcode].to_s.strip
      return render json: { ok: false, error: "barcode required" }, status: :bad_request if barcode.blank?

      quantity = params[:quantity].to_i
      quantity = 1 if quantity <= 0

      sku = Sku.find_by(barcode: barcode)
      return render json: { ok: false, error: "SKU not found" }, status: :not_found unless sku

      idempotency_key =
        params[:idempotency_key].presence ||
        "pos:scan:#{barcode}:#{Time.current.to_i}:#{SecureRandom.hex(4)}"

      before = sku_snapshot(sku)
      frozen_before = before.dig(:balance, :frozen_at).present?

      balance = Inventory::BalanceFetcher.fetch_for_update!(sku: sku)
      on_hand_before = balance.on_hand.to_i

      if on_hand_before < quantity
        log_pos_info(
          event: "pos.scan.commit.rejected",
          reason: "not_enough_stock",
          barcode: barcode,
          sku: sku.code,
          quantity: quantity,
          on_hand: on_hand_before
        )
        return render json: { ok: false, error: "Not enough stock" }, status: :unprocessable_entity
      end

      result = Inventory::CommitPos.call!(
        sku: sku,
        quantity: quantity,
        idempotency_key: idempotency_key,
        meta: { source: "pos_scan_direct" }
      )

      oversell_result = Inventory::OversellGuard.call!(
        sku: sku,
        trigger: "pos_scan_direct",
        idempotency_key: "oversell:pos_scan_direct:sku=#{sku.id}:request=#{idempotency_key}",
        meta: {
          source: "pos_scan_direct",
          barcode: barcode
        }
      )

      after = sku_snapshot(sku.reload)

      log_pos_info(
        event: "pos.scan.commit",
        sku: sku.code,
        barcode: barcode,
        quantity: quantity,
        idempotency_key: idempotency_key,
        result: result,
        oversell_result: oversell_result,
        note: (frozen_before ? "commit_while_frozen" : nil),
        before: before,
        after: after
      )

      render json: {
        ok: true,
        result: result,
        oversell_result: oversell_result,
        idempotency_key: idempotency_key,
        sku: { id: sku.id, code: sku.code, barcode: sku.barcode },
        before: before,
        after: after
      }
    rescue Inventory::CommitPos::OnHandWouldGoNegative => e
      log_pos_info(
        event: "pos.scan.commit.rejected",
        reason: "not_enough_stock",
        barcode: params[:barcode].to_s,
        quantity: params[:quantity].to_i,
        err_class: e.class.name,
        err_message: e.message
      )
      render json: { ok: false, error: "Not enough stock" }, status: :unprocessable_entity
    end
  end
end
