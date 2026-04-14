# frozen_string_literal: true

if Rails.env.development?
  base = ActiveSupport::Logger.new($stdout)
  base.formatter = Rails.application.config.log_formatter
  base.level = Logger::INFO

  tagged = ActiveSupport::TaggedLogging.new(base)

  Rails.logger = tagged
  Rails.application.config.logger = tagged
end
