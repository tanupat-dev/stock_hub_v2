# frozen_string_literal: true

class TiktokApp < ApplicationRecord
  has_many :tiktok_credentials, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true
  validates :auth_region, presence: true
  validates :service_id, :app_key, :app_secret, :open_api_host, presence: true

  scope :active, -> { where(active: true) }

  def authorize_base_url
    auth_region.to_s.upcase == "US" ? "https://services.tiktokshops.us" : "https://services.tiktokshop.com"
  end
end