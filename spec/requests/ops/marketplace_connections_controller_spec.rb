# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ops::MarketplaceConnectionsController", type: :request do
  let(:json_headers) { { "ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json" } }

  describe "POST /ops/marketplace_connections" do
    it "returns JSON bad_request for unsupported channel" do
      post "/ops/marketplace_connections",
           params: { channel: "bad_channel" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("unsupported channel")
    end

    it "returns JSON bad_request when channel is missing" do
      post "/ops/marketplace_connections",
           params: {}.to_json,
           headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to be_present
    end

    it "returns JSON when unexpected error occurs for tiktok" do
      allow_any_instance_of(Ops::MarketplaceConnectionsController)
        .to receive(:create_or_update_tiktok_connection!)
        .and_raise(StandardError, "boom create")

      post "/ops/marketplace_connections",
           params: { channel: "tiktok" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom create")
    end
  end

  describe "DELETE /ops/marketplace_connections/:id" do
    it "returns JSON not_found" do
      delete "/ops/marketplace_connections/999999999", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("shop not found")
    end

    it "returns JSON when unexpected error occurs" do
      allow(Shop).to receive(:find).and_raise(StandardError, "boom destroy")

      delete "/ops/marketplace_connections/1", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom destroy")
    end
  end
end
