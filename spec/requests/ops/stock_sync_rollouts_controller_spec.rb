# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ops::StockSyncRolloutsController", type: :request do
  describe "GET /ops/stock_sync_rollout" do
    it "returns JSON on success" do
      allow(StockSync::RolloutState).to receive(:call).and_return(
        {
          global_enabled: false,
          prefix_mode: "allowlist",
          rollout_prefixes: [],
          shops: []
        }
      )

      get "/ops/stock_sync_rollout", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body["rollout"]).to be_present
    end

    it "returns JSON when unexpected error occurs" do
      allow(StockSync::RolloutState).to receive(:call).and_raise(StandardError, "boom rollout")

      get "/ops/stock_sync_rollout", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom rollout")
    end
  end

  describe "PATCH /ops/stock_sync_rollout/global" do
    it "returns JSON on success" do
      allow(StockSync::Rollout).to receive(:set_global_enabled!).with(true)
      allow(StockSync::Rollout).to receive(:global_enabled?).and_return(true)

      patch "/ops/stock_sync_rollout/global?enabled=true",
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body["global_enabled"]).to eq(true)
    end
  end

  describe "PATCH /ops/stock_sync_rollout/prefix_mode" do
    it "returns JSON validation error for invalid mode" do
      patch "/ops/stock_sync_rollout/prefix_mode?mode=bad",
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("invalid_mode")
    end
  end

  describe "PATCH /ops/stock_sync_rollout/prefix_list" do
    it "returns JSON validation error when prefixes is not array" do
      patch "/ops/stock_sync_rollout/prefix_list",
            params: { prefixes: "bad" }.to_json,
            headers: {
              "ACCEPT" => "application/json",
              "CONTENT_TYPE" => "application/json"
            }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("prefixes_must_be_array")
    end
  end

  describe "PATCH /ops/stock_sync_rollout_shops/:id/toggle" do
    it "returns JSON not_found when shop does not exist" do
      patch "/ops/stock_sync_rollout_shops/999999/toggle?enabled=true",
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("not found")
    end
  end

  describe "POST /ops/stock_sync_rollout_shops/:id/backfill" do
    it "returns JSON not_found when shop does not exist" do
      post "/ops/stock_sync_rollout_shops/999999/backfill",
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("not found")
    end
  end
end
