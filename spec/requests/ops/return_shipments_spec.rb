# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ops::ReturnShipments", type: :request do
  describe "GET /ops/return_shipments" do
    it "returns JSON (not HTML)" do
      get "/ops/return_shipments", headers: { "ACCEPT" => "application/json" }

      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
    end

    it "returns JSON even when error occurs" do
      allow(ReturnShipment).to receive(:includes).and_raise(StandardError, "boom")

      get "/ops/return_shipments", headers: { "ACCEPT" => "application/json" }

      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end
end