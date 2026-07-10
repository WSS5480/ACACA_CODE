# config/initializers/cors.rb
allowed_origins = ENV.fetch('ALLOWED_ORIGINS', 'http://localhost:3000,http://localhost:3001,http://localhost:3008,http://localhost:8000,https://www-acasa.vercel.app,https://www-acasa-*.vercel.app').split(',')

dynamic_origin_matchers = [
  /\Ahttp:\/\/localhost:\d+\z/i,
  /\Ahttp:\/\/127\.0\.0\.1:\d+\z/i,
  /\Ahttp:\/\/\d{1,3}(?:\.\d{1,3}){3}:\d+\z/i,
  /\Ahttps:\/\/\d{1,3}(?:\.\d{1,3}){3}:\d+\z/i,
  /\Ahttps:\/\/.*\.vercel\.app\z/i  # Allow all Vercel preview deployments
]

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins do |source, _env|
      next true if source.nil?
      allowed_origins.include?(source) || dynamic_origin_matchers.any? { |regex| regex.match?(source) }
    end

    resource '*',
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: ['Authorization'],
      credentials: true
  end
end
