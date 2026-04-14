# frozen_string_literal: true

module Ops
  class ProductsController < BaseController
    def index
      @active_ops_nav = :products
    end
  end
end
