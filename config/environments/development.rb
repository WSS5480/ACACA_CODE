require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.cache_store = :memory_store
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false
    config.cache_store = :null_store
  end

  config.active_storage.service = ENV['AWS_ACCESS_KEY_ID'].present? ? :amazon : :local

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_job.verbose_enqueue_logs = true

  config.action_mailer.default_url_options = {
    host: ENV['API_HOST'] || 'localhost:3000',
    protocol: ENV['API_PROTOCOL'] || 'http'
  }

  config.action_controller.raise_on_missing_callback_actions = true

  config.x.api_consumer_host = ENV['FRONT_HOST'] || 'http://localhost:3000'
  # Real SMTP (e.g. Titan) when SMTP_ADDRESS is set in .env; otherwise fall back
  # to letter_opener (which just saves emails to tmp/letter_opener/).
  if ENV['SMTP_ADDRESS'].present?
    smtp_port = (ENV['SMTP_PORT'] || 587).to_i
    smtp = {
      address: ENV['SMTP_ADDRESS'],
      port: smtp_port,
      user_name: ENV['SMTP_USERNAME'],
      password: ENV['SMTP_PASSWORD'],
      domain: ENV['SMTP_DOMAIN'] || 'acasa-us.com',
      authentication: :login
    }
    # Port 465 uses implicit SSL (e.g. GoDaddy smtpout.secureserver.net);
    # 587 uses STARTTLS (e.g. standalone smtp.titan.email).
    if smtp_port == 465
      smtp[:ssl] = true
    else
      smtp[:enable_starttls_auto] = true
    end
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = smtp
  else
    config.action_mailer.delivery_method = :letter_opener
  end

  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true

  # Allow access through a public tunnel (Cloudflare/ngrok) for partner demos.
  config.hosts.clear

  # Needed so Active Storage can build product image URLs in development.
  Rails.application.routes.default_url_options = { host: 'localhost', port: 3000 }
  config.action_controller.default_url_options = { host: 'localhost', port: 3000 }
end
