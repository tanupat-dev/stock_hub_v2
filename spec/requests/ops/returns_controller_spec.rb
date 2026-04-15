# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ops::ReturnsController", type: :request do
  describe "GET /ops/returns/shops" do
    it "returns JSON on success" do
      get "/ops/returns/shops", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body).to have_key("shops")
    end

    it "returns JSON when unexpected error occurs" do
      relation = instance_double(ActiveRecord::Relation)
      allow(Shop).to receive(:where).and_return(relation)
      allow(relation).to receive(:order).and_raise(StandardError, "boom shops")

      get "/ops/returns/shops", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom shops")
    end
  end
end
