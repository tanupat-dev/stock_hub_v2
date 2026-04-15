# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pos::StockCountsController", type: :request do
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

  describe "POST /pos/stock_counts" do
    it "returns JSON bad_request when idempotency_key is missing" do
      allow_any_instance_of(Pos::StockCountsController)
        .to receive(:find_pos_shop!)
        .and_return(double("Shop"))

      post "/pos/stock_counts", headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end

  describe "GET /pos/stock_counts/:id" do
    it "returns JSON not_found" do
      get "/pos/stock_counts/999999", headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end

  describe "POST /pos/stock_counts/:id/upsert_line" do
    it "returns JSON not_found when session does not exist" do
      post "/pos/stock_counts/999999/upsert_line",
           params: {
             sku_id: 1,
             counted_qty: 5,
             idempotency_key: "k1"
           }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end

  describe "POST /pos/stock_counts/:id/confirm" do
    it "returns JSON not_found when session does not exist" do
      post "/pos/stock_counts/999999/confirm",
           params: { idempotency_key: "k2" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end
end
