# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Errors
      class Error < StandardError
        attr_reader :code, :request_id

        def initialize(message = nil, code: nil, request_id: nil)
          super(message)
          @code = code
          @request_id = request_id
        end
      end

      # ใช้กับ 36009003 หรือ HTTP 5xx/timeout ฯลฯ
      class TransientError < Error; end

      # rate limit / too many requests
      class RateLimitedError < Error; end

      # access token invalid/expired/unauthorized
      class UnauthorizedError < Error; end

      # signature invalid
      class SignatureInvalidError < Error; end
    end
  end
end