# frozen_string_literal: true

class TiktokCredential < ApplicationRecord
  belongs_to :tiktok_app
  has_many :shops, dependent: :nullify

  validates :open_id, presence: true, uniqueness: { scope: :tiktok_app_id }
  validates :access_token, :refresh_token, presence: true

  def access_token_expiring_soon?(within: 5.minutes)
    access_token_expires_at <= Time.current + within
  end

  def refresh_token_expired?
    refresh_token_expires_at <= Time.current
  end
end