require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}"
  }

  # Storage:
  # - local => use persistent disk mounted at /rails/storage
  # - can switch later via ENV without code changes
  config.active_storage.service =
    ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym

  # Assume SSL is terminated by the platform proxy/load balancer.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip redirect for health check endpoint so platform probes stay simple.
  config.ssl_options = {
    redirect: {
      exclude: ->(request) { request.path == "/up" }
    }
  }

  # Log to STDOUT with request id tag.
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Default log level.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging logs.
  config.silence_healthcheck_path = "/up"

  # Don't log deprecations in production.
  config.active_support.report_deprecations = false

  # Rails 8 solid stack
  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue

  # Mailer host
  app_host = ENV.fetch("APP_HOST")
  config.action_mailer.default_url_options = {
    host: app_host,
    protocol: "https"
  }

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Host authorization
  config.hosts << app_host
  config.host_authorization = {
    exclude: ->(request) { request.path == "/up" }
  }
end