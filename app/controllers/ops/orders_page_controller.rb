# frozen_string_literal: true

module Ops
  class OrdersPageController < BaseController
    def index
      @active_ops_nav = :orders
    end
  end
end
