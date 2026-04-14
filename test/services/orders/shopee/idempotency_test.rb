# frozen_string_literal: true

require "test_helper"

module Orders
  module Shopee
    class IdempotencyTest < ActiveSupport::TestCase
      test "policy_prefix builds canonical shopee prefix" do
        prefix = Orders::Shopee::Idempotency.policy_prefix("2603240MJVYX45")
        assert_equal "shopee:order:2603240MJVYX45", prefix
      end

      test "validate_policy_prefix! rejects invalid namespace" do
        assert_raises(ArgumentError) do
          Orders::Shopee::Idempotency.validate_policy_prefix!("shoopee:order:2603240MJVYX45")
        end
      end

      test "validate_policy_prefix! rejects suspicious typo" do
        assert_raises(ArgumentError) do
          Orders::Shopee::Idempotency.validate_policy_prefix!("shopee:orrder:2603240MJVYX45")
        end
      end
    end
  end
end
