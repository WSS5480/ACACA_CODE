require 'sidekiq/web'
require 'sidekiq-scheduler/web'

Rails.application.routes.draw do
  sidekiq_user = ENV["SIDEKIQ_USERNAME"].presence
  sidekiq_pass = ENV["SIDEKIQ_PASSWORD"].presence

  if Rails.env.production? && (sidekiq_user.nil? || sidekiq_pass.nil?)
    Rails.logger.warn("[sidekiq] SIDEKIQ_USERNAME/SIDEKIQ_PASSWORD no configuradas: el panel /sidekiq queda deshabilitado en produccion")
  else
    sidekiq_user ||= "admin"
    sidekiq_pass ||= "password"

    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, sidekiq_user) &
        ActiveSupport::SecurityUtils.secure_compare(password, sidekiq_pass)
    end

    mount Sidekiq::Web => '/sidekiq'
  end

  get "up" => "rails/health#show", as: :rails_health_check

  get 'password/edit', to: 'devise/passwords#edit', as: :custom_password_edit

  scope '/api' do
    devise_for :users, path: '', path_names: {
      sign_in: 'login',
      sign_out: 'logout',
      registration: 'signup'
    },
    controllers: {
      sessions: 'users/sessions',
      registrations: 'users/registrations',
      confirmations: 'users/confirmations'
    }

    resources :roles, controller: 'api/roles' do
      post 'seed', on: :collection
    end

    get  'settings/rainforest',      to: 'api/settings#rainforest'
    put  'settings/rainforest',      to: 'api/settings#update_rainforest'
    post 'settings/rainforest/test', to: 'api/settings#test_rainforest'

    # Plantilla editable del contrato de venta a crédito (Seguridad → Contrato)
    get 'settings/contract', to: 'api/settings#contract_template'
    put 'settings/contract', to: 'api/settings#update_contract_template'

    # Aviso de privacidad editable (GET público: lo muestra www.acasamx.com/privacidad)
    get 'settings/privacy', to: 'api/settings#privacy'
    put 'settings/privacy', to: 'api/settings#update_privacy'

    # Preguntas de aprobación (Motor de riesgo): pre-aprobación y aprobación final
    get 'settings/approval_questions', to: 'api/settings#approval_questions'
    put 'settings/approval_questions', to: 'api/settings#update_approval_questions'
    get 'settings/wa_responses',       to: 'api/settings#wa_responses'
    put 'settings/wa_responses',       to: 'api/settings#update_wa_responses'

    # Soporte con tickets (pagina bajo la linea)
    get  'support/tickets',           to: 'api/support_tickets#index'
    post 'support/tickets',           to: 'api/support_tickets#create'
    get  'support/tickets/:id',       to: 'api/support_tickets#show'
    put  'support/tickets/:id',       to: 'api/support_tickets#update'
    post 'support/tickets/:id/notes', to: 'api/support_tickets#create_note'

    # Tasas e impuestos (Seguridad): IVA, tasa de interés (define los factores) y seguro/waiver
    get 'settings/rates', to: 'api/settings#rates'
    put 'settings/rates', to: 'api/settings#update_rates'

    resources :products, controller: 'api/products' do
      post 'manage_collection', on: :collection
      post 'import_search', on: :collection
      post 'rainforest_category', on: :collection
      post 'rainforest_search', on: :collection
      post 'check_sellers', on: :collection
      post 'verify_availability', on: :collection
      post 'import_selected', on: :collection
      get 'rainforest_categories', on: :collection
      post 'import_file', on: :collection
      post 'bulk_update', on: :collection
      post 'bulk_delete', on: :collection
      delete 'reset', on: :collection
      get 'download_csv', on: :collection
      post 'update_csv', on: :collection
      get 'track_csv_job/:job_id', action: :track_csv_job, on: :collection
    end

    resources :categories, controller: 'api/categories'

    resources :users, controller: 'api/users' do
      post 'client_register', on: :collection
      post 'set_credit', on: :member
      post 'confirm_account', on: :member # override manual de la verificación por WhatsApp (solo master/admin)
      post 'send_password_setup', on: :member
      get 'full_info', on: :member
    end

    get 'current_user', to: 'api/users#current_user'

    # Verificacion de cuenta por WhatsApp (mensaje entrante del cliente)
    get  'verifications/status', to: 'api/verifications#status'
    get  'whatsapp/webhook',     to: 'api/whatsapp_webhook#verify'
    post 'whatsapp/webhook',     to: 'api/whatsapp_webhook#receive'

    resources :exchange_rates, controller: 'api/exchange_rates', only: [:index, :show, :create, :destroy] do
      post 'refresh', on: :collection
    end

    resources :orders, controller: 'api/orders' do
      post 'verify', on: :member
      post 'confirm_delivery', on: :member
      get 'simulate_payment_plans', on: :collection
      get 'dashboard', on: :collection
      put 'assign_beneficiary', on: :member
    end

    resources :contracts, controller: 'api/contracts', only: [:index, :show, :create, :destroy] do
      post 'record_payment', on: :member
      post 'autopay', on: :member
      post 'generate_document', on: :member # staff: genera el contrato desde la plantilla y avisa por WhatsApp
      post 'sign', on: :member              # cliente: firma electrónica (imagen)
      post 'set_next_due', on: :member      # staff: mover el próximo vencimiento (PRUEBAS de cobranza)
      post 'confirm_datos', on: :member     # cliente que regresa: reutilizar/confirmar sus datos verificados
      post 'set_status', on: :member        # staff: devuelto / castigado / reactivar (bitácora)
      post 'set_frequency', on: :member     # cliente/staff: semanal | quincenal | mensual (recalcula calendario)
      post 'autopay_all', on: :collection   # cliente: pago automático de TODA la cuenta
    end

    resources :beneficiaries, controller: 'api/beneficiaries'
    resources :buyers, controller: 'api/buyers'
    resources :referrals, controller: 'api/referrals'
    resources :guarantors, controller: 'api/guarantors'

    resources :zip_codes, controller: 'api/zip_codes' do
      post 'populate', on: :collection
    end

    # Restablecimiento de contraseña por enlace de correo
    post 'passwords/forgot', to: 'api/passwords#forgot'
    post 'passwords/reset',  to: 'api/passwords#reset'

    post 'clients/forgot_number', to: 'api/clients#forgot_number'
    put 'clients/:id/update_credit', to: 'api/clients#update_credit'

    get  'risk_engine/versions', to: 'api/risk_engine_configs#index'
    post 'risk_engine/versions', to: 'api/risk_engine_configs#create'
    post 'risk_engine/versions/:version/activate', to: 'api/risk_engine_configs#activate'
    post 'risk_engine/recalc_credit', to: 'api/risk_engine_configs#recalc_credit'

    post 'stripe/payment_intent',  to: 'api/stripe#payment_intent'
    post 'stripe/charge_saved',    to: 'api/stripe#charge_saved'
    post 'stripe/finalize',        to: 'api/stripe#finalize'
    get  'stripe/payment_methods', to: 'api/stripe#payment_methods'
    post 'stripe/setup_intent',    to: 'api/stripe#setup_intent'          # guardar tarjeta sin pagar (Perfil)
    post 'stripe/multi_payment_intent', to: 'api/stripe#multi_payment_intent' # un pago que cubre varios contratos
    delete 'stripe/payment_methods/:id', to: 'api/stripe#detach_payment_method'
    get  'stripe/config',          to: 'api/stripe#publishable_config'
    post 'stripe/webhook',         to: 'api/stripe#webhook'

    get  'whatsapp/messages', to: 'api/whatsapp_messages#index'
    post 'whatsapp/send',     to: 'api/whatsapp_messages#create'
    # Bandeja de WhatsApp del admin: hilos por persona + no leídos
    get  'whatsapp/threads',      to: 'api/whatsapp_messages#threads'
    post 'whatsapp/read',         to: 'api/whatsapp_messages#mark_read'
    get  'whatsapp/unread_count', to: 'api/whatsapp_messages#unread_count'
    # Plantillas: listar, CREAR (constructor del admin), eliminar y mapear avisos automáticos
    get    'whatsapp/templates',      to: 'api/whatsapp_messages#templates'
    post   'whatsapp/templates',      to: 'api/whatsapp_messages#create_template'
    delete 'whatsapp/templates',      to: 'api/whatsapp_messages#destroy_template'
    put    'whatsapp/auto_templates', to: 'api/whatsapp_messages#auto_templates'
    delete 'whatsapp/messages/:id', to: 'api/whatsapp_messages#destroy' # solo master/admin
    delete 'whatsapp/threads',      to: 'api/whatsapp_messages#destroy_thread' # conversación completa (solo master/admin)
    get  'whatsapp/contacts',       to: 'api/whatsapp_messages#contacts' # directorio completo para Nuevo chat

    # Marketing en redes (Facebook + Instagram) — pestaña Marketing
    get  'marketing/overview', to: 'api/marketing#overview'
    get  'marketing/posts',    to: 'api/marketing#posts'
    get  'marketing/comments', to: 'api/marketing#comments'
    post 'marketing/publish',  to: 'api/marketing#publish'
    post 'marketing/reply',    to: 'api/marketing#reply'
    # Biblioteca de publicaciones (textos guardados para revisar/editar antes de postear)
    get  'marketing/library',  to: 'api/marketing#library'
    put  'marketing/library',  to: 'api/marketing#save_library'

    # Bitácora de conversaciones (notas de llamadas) por persona
    resources :contact_logs, controller: 'api/contact_logs', only: [:index, :create, :destroy] do
      post 'email', on: :collection # correo del equipo al cliente (queda en su bitácora)
    end

    # Bitácora de AUDITORÍA (solo master/admin): quién hizo qué — cambios de tasas,
    # pagos, aprobaciones, entregas, firmas, eliminaciones...
    resources :audit_logs, controller: 'api/audit_logs', only: [:index]

    # Cambios sensibles con FIRMAS de administradores (tasas, documentos legales,
    # revocaciones de acceso del equipo): 4 firmas, o todas si hay menos de 4.
    resources :change_requests, controller: 'api/change_requests', only: [:index] do
      post 'sign', on: :member
      post 'reject', on: :member
    end

    # CRM: cuentas nuevas que nunca compraron (contactar o LIBERAR)
    get  'crm/leads',             to: 'api/leads#index'
    post 'crm/leads/:id/dismiss', to: 'api/leads#dismiss'

    # Carritos abandonados (CRM): el storefront reporta el carrito del cliente
    post 'carts/track', to: 'api/carts#track'
    get  'carts',       to: 'api/carts#index'
    delete 'carts/:id', to: 'api/carts#destroy'

    # Compromisos de pago (cobranza): aviso al registrarlo + recordatorio del día anterior
    resources :commitments, controller: 'api/commitments', only: [:index, :create, :update] do
      post 'run_reminders', on: :collection
    end

    post 'autopay/run', to: 'api/autopay#run'
    # Tick programado (Cron Job de Render cada 15 min; corre lo recurrente)
    post 'ticks/run', to: 'api/ticks#run'
  end
end
