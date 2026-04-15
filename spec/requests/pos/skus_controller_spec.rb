# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Pos::SkusController", type: :request do
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

  describe "GET /pos/skus/facets" do
    it "returns JSON on success" do
      get "/pos/skus/facets", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body).to have_key("facets")
    end

    it "returns JSON when unexpected error occurs" do
      allow(Sku).to receive(:all).and_raise(StandardError, "boom facets")

      get "/pos/skus/facets", headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom facets")
    end
  end

  describe "GET /pos/skus/search" do
    it "returns JSON on success" do
      get "/pos/skus/search", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body).to have_key("skus")
    end

    it "returns JSON when unexpected error occurs" do
      allow(Sku).to receive(:all).and_raise(StandardError, "boom search")

      get "/pos/skus/search", headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom search")
    end
  end

  describe "GET /pos/skus/:id/ledger" do
    it "returns JSON not_found" do
      get "/pos/skus/999999999/ledger", headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("SKU not found")
    end

    it "returns JSON when unexpected error occurs" do
      relation = instance_double(ActiveRecord::Relation)
      allow(Sku).to receive(:includes).and_return(relation)
      allow(relation).to receive(:find).and_raise(StandardError, "boom ledger")

      get "/pos/skus/1/ledger", headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom ledger")
    end
  end

  describe "POST /pos/skus/:id/freeze" do
    it "returns JSON not_found" do
      post "/pos/skus/999999999/freeze",
           params: { idempotency_key: "k1" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("SKU not found")
    end

    it "returns JSON when unexpected error occurs" do
      allow(Sku).to receive(:find).and_raise(StandardError, "boom freeze")

      post "/pos/skus/1/freeze",
           params: { idempotency_key: "k2" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom freeze")
    end
  end

  describe "POST /pos/skus/:id/unfreeze" do
    it "returns JSON not_found" do
      post "/pos/skus/999999999/unfreeze",
           params: { idempotency_key: "k3" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("SKU not found")
    end

    it "returns JSON when unexpected error occurs" do
      allow(Sku).to receive(:find).and_raise(StandardError, "boom unfreeze")

      post "/pos/skus/1/unfreeze",
           params: { idempotency_key: "k4" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
      expect(body["error"]).to eq("boom unfreeze")
    end
  end
end
