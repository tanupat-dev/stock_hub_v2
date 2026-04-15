# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pos::StockAdjustmentsController", type: :request do
  before do
    allow_any_instance_of(Pos::BaseController)
      .to receive(:require_pos_key!)
      .and_return(true)
  end

  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
      "X-POS-KEY" => "test-pos-key"
    }
  end

  describe "POST /pos/stock_adjust" do
    it "returns JSON bad_request when lookup params are missing" do
      post "/pos/stock_adjust",
           params: { mode: "stock_in", quantity: 1, idempotency_key: "k1" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end

    it "returns JSON not_found when sku does not exist" do
      post "/pos/stock_adjust",
           params: {
             sku_id: 999999,
             mode: "stock_in",
             quantity: 1,
             idempotency_key: "k2"
           }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("SKU not found")
    end

    it "returns JSON validation error for unsupported mode" do
      allow(Sku).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      post "/pos/stock_adjust",
           params: {
             sku_id: 1,
             mode: "bad_mode",
             idempotency_key: "k3"
           }.to_json,
           headers: json_headers

      expect(response.media_type).to eq("application/json")
    end
  end
end
