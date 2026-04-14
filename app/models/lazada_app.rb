# app/models/lazada_app.rb
# frozen_string_literal: true

class LazadaApp < ApplicationRecord
  has_many :lazada_credentials, dependent: :restrict_with_exception
  has_many :shops, dependent: :nullify

  validates :code, presence: true, uniqueness: true
  validates :app_key, presence: true
  validates :app_secret, presence: true
  validates :auth_host, presence: true
  validates :api_host, presence: true
end
