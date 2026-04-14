# app/models/lazada_credential.rb
# frozen_string_literal: true

class LazadaCredential < ApplicationRecord
  belongs_to :lazada_app
  has_many :shops, dependent: :nullify

  validates :access_token, presence: true
  validates :refresh_token, presence: true

  def access_token_expired?
    return true if expires_at.blank?
    expires_at <= 5.minutes.from_now
  end

  def refresh_token_expired?
    return true if refresh_expires_at.blank?
    refresh_expires_at <= 1.day.from_now
  end
end
