class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # --- Límites de autenticación (mitigan fuerza bruta) ---
  # Devise (bajo scope /api, path '') expone:
  #   POST /api/login    -> inicio de sesión
  #   POST /api/signup   -> registro
  #   POST /api/password -> solicitud de restablecimiento de contraseña

  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/api/login"
  end

  throttle("signup/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/api/signup"
  end

  throttle("password-reset/ip", limit: 5, period: 5.minutes) do |req|
    req.ip if req.post? && req.path == "/api/password"
  end

  # Respuesta cuando se supera un límite (rack-attack 6.x usa throttled_responder).
  self.throttled_responder = lambda do |request|
    match_data  = request.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period].to_i

    body = I18n.t(
      "errors.messages.rate_limited",
      default: "Demasiados intentos. Inténtalo de nuevo más tarde."
    )

    headers = {
      "Content-Type" => "text/plain; charset=utf-8",
      "Retry-After"  => retry_after.positive? ? retry_after.to_s : "60"
    }

    [429, headers, [body]]
  end
end
