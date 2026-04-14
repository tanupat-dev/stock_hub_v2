# frozen_string_literal: true

require_relative "boot"
require "rails/all"
require "solid_queue"
Bundler.require(*Rails.groups)

module StockHubV2
  class Application < Rails::Application
    config.load_defaults 8.0

    config.autoload_lib(ignore: %w[assets tasks])

    # ✅ Solid Queue (Rails 8 official stack)
    config.active_job.queue_adapter = :solid_queue

    # (optional) ตั้ง timezone ถ้าจะให้ consistent
    # config.time_zone = "Bangkok"
  end
end