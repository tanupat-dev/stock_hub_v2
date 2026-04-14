# test/test_helper.rb
# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

# ✅ Disable Solid Queue recurring in test (กันมัน enqueue เอง)
if defined?(SolidQueue::Recurring)
  SolidQueue::Recurring.disable!
end

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # ✅ กัน state แปลกๆ ตอนนี้
    parallelize(workers: 1)

    self.use_transactional_tests = true

    setup do
      clear_enqueued_jobs
      clear_performed_jobs
    end
  end
end