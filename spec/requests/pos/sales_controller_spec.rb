# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Pos::SalesController", type: :request do
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

  describe "POST /pos/sales" do
    it "returns JSON bad_request when idempotency_key is missing" do
      allow_any_instance_of(Pos::SalesController)
        .to receive(:find_pos_shop!)
        .and_return(double("Shop"))

      post "/pos/sales", headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to be_present
    end

    it "returns JSON when unexpected error occurs" do
      allow_any_instance_of(Pos::SalesController).to receive(:find_pos_shop!).and_raise(StandardError, "boom create")

      post "/pos/sales", params: { idempotency_key: "k1" }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom create")
    end
  end

  describe "GET /pos/sales" do
    it "returns JSON on success" do
      get "/pos/sales", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body).to have_key("sales")
    end

    it "returns JSON bad_request for invalid date" do
      get "/pos/sales", params: { date_from: "not-a-date" }, headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("invalid date")
    end
  end

  describe "GET /pos/sales/:id" do
    it "returns JSON not_found" do
      get "/pos/sales/999999999", headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("sale not found")
    end

    it "returns JSON when unexpected error occurs" do
      relation = instance_double(ActiveRecord::Relation)
      allow(PosSale).to receive(:includes).and_return(relation)
      allow(relation).to receive(:find).and_raise(StandardError, "boom show")

      get "/pos/sales/1", headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom show")
    end
  end

  describe "POST /pos/sales/:id/add_line" do
    it "returns JSON not_found when sale does not exist" do
      post "/pos/sales/999999999/add_line",
           params: { barcode: "abc", quantity: 1, idempotency_key: "k2" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end

    it "returns JSON when unexpected error occurs" do
      allow(PosSale).to receive(:find).and_raise(StandardError, "boom add_line")

      post "/pos/sales/1/add_line",
           params: { barcode: "abc", quantity: 1, idempotency_key: "k3" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom add_line")
    end
  end

  describe "PATCH /pos/sales/:id/update_line" do
    it "returns JSON bad_request when line_id is missing" do
      patch "/pos/sales/1/update_line",
            params: { quantity: 2, idempotency_key: "k4" }.to_json,
            headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end

  describe "DELETE /pos/sales/:id/remove_line" do
    it "returns JSON bad_request when line_id is missing" do
      delete "/pos/sales/1/remove_line",
             params: { idempotency_key: "k5" }.to_json,
             headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end

  describe "POST /pos/sales/:id/checkout" do
    it "returns JSON not_found when sale does not exist" do
      post "/pos/sales/999999999/checkout",
           params: { idempotency_key: "k6" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end

  describe "POST /pos/sales/:id/void" do
    it "returns JSON not_found when sale does not exist" do
      post "/pos/sales/999999999/void",
           params: { idempotency_key: "k7" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end
end
