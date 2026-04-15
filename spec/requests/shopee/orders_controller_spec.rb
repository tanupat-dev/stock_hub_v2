# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe "Shopee::OrdersController", type: :request do
  def uploaded_xlsx_file
    file = Tempfile.new([ "orders", ".xlsx" ])
    file.binmode
    file.write("fake xlsx")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  describe "POST /shopee/orders/import" do
    it "returns JSON when file is missing" do
      post "/shopee/orders/import", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(false)
    end
  end
end
