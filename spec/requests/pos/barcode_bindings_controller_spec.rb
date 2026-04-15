# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pos::BarcodeBindingsController", type: :request do
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

  describe "POST /pos/barcode_bindings" do
    it "returns JSON bad_request when sku_id and sku_code are missing" do
      post "/pos/barcode_bindings",
           params: { barcode: "123456" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end

    it "returns JSON not_found when sku does not exist" do
      post "/pos/barcode_bindings",
           params: { sku_id: 999999, barcode: "123456" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("SKU not found")
    end
  end
end
