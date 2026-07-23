require 'sidekiq-scheduler'

Sidekiq.configure_server do |config|
  #config.redis = { url: 'redis://localhost:6379/0' }
  config.redis = { url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } }

  config.on(:startup) do
    schedule_file = Rails.root.join('config/sidekiq_schedule.yml')

    if File.exist?(schedule_file) && File.size(schedule_file).positive?
      schedule = YAML.safe_load_file(schedule_file)
      if schedule.is_a?(Hash) && schedule.any?
        Sidekiq.schedule = schedule
        SidekiqScheduler::Scheduler.instance.reload_schedule!
      end
    end
  end
end

Sidekiq.configure_client do |config|
  #config.redis = { url: 'redis://localhost:6379/0' }
  config.redis = { url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } }
end
