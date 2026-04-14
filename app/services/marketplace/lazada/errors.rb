# frozen_string_literal: true

module Marketplace
  module Lazada
    module Errors
      class Error < StandardError; end
      class TransientError < Error; end
      class RateLimitedError < Error; end
      class BusinessError < Error; end
    end
  end
end
