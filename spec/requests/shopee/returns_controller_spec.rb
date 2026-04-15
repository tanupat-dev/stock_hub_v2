# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Shopee::ReturnsController", type: :request do
  describe "POST /shopee/returns/import" do
    it "returns JSON when file is missing" do
      post "/shopee/returns/import", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end
end
