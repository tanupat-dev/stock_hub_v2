# frozen_string_literal: true

module Ops
  class PosCashierController < BaseController
    def index
      @active_ops_nav = :pos_cashier
    end
  end
end
