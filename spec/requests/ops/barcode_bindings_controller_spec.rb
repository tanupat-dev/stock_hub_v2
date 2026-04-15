# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ops::BarcodeBindingsController", type: :request do
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json"
    }
  end

  describe "POST /ops/barcode_bindings/clear" do
    it "returns JSON bad_request when sku_id and sku_code are missing" do
      post "/ops/barcode_bindings/clear",
           params: {}.to_json,
           headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end

    it "returns JSON not_found when sku does not exist" do
      post "/ops/barcode_bindings/clear",
           params: { sku_id: 999999 }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("SKU not found")
    end
  end
end
