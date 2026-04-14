# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :shop

  has_many :order_lines, dependent: :destroy
  has_many :return_shipments, dependent: :nullify

  validates :external_order_id, presence: true, uniqueness: { scope: %i[channel shop_id] }
  validates :channel, presence: true
  validates :status, presence: true
end
