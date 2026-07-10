require 'sidekiq/web'
require 'sidekiq-scheduler/web'

Rails.application.routes.draw do
  #devise_for :users#Default route for users is rewritten
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Sidekiq Web UI con autenticación básica.
  # En producción se EXIGEN SIDEKIQ_USERNAME y SIDEKIQ_PASSWORD: nunca se expone
  # el panel con las credenciales por defecto (admin/password). Si no están
  # configuradas en producción, el panel simplemente no se monta.
  sidekiq_user = ENV["SIDEKIQ_USERNAME"].presence
  sidekiq_pass = ENV["SIDEKIQ_PASSWORD"].presence

  if Rails.env.production? && (sidekiq_user.nil? || sidekiq_pass.nil?)
    Rails.logger.warn("[sidekiq] SIDEKIQ_USERNAME/SIDEKIQ_PASSWORD no configuradas: el panel /sidekiq queda deshabilitado en producción")
  else
    # Valores por defecto solo para desarrollo/entornos no productivos.
    sidekiq_user ||= "admin"
    sidekiq_pass ||= "password"

    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, sidekiq_user) &
        ActiveSupport::SecurityUtils.secure_compare(password, sidekiq_pass)
    end

    mount Sidekiq::Web => '/sidekiq'
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  # Custom route for password edit outside of api scope so in the password reset mailer it removes the /api/ prefix in the url
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

    resources :products, controller: 'api/products' do
      post 'manage_collection', on: :collection
      delete 'reset', on: :collection
      get 'download_csv', on: :collection
      post 'update_csv', on: :collection
      get 'track_csv_job/:job_id', action: :track_csv_job, on: :collection
    end

    resources :categories, controller: 'api/categories'

    resources :users, controller: 'api/users' do
      post 'client_register', on: :collection
    end

    get 'current_user', to: 'api/users#current_user'

    resources :exchange_rates, controller: 'api/exchange_rates', only: [:index, :show, :create, :destroy]

    resources :orders, controller: 'api/orders' do
      get 'simulate_payment_plans', on: :collection
      get 'dashboard', on: :collection
      put 'assign_beneficiary', on: :member
    end

    resources :beneficiaries, controller: 'api/beneficiaries'

    resources :buyers, controller: 'api/buyers'

    resources :referrals, controller: 'api/referrals'

    resources :guarantors, controller: 'api/guarantors'

    resources :zip_codes, controller: 'api/zip_codes' do
      post 'populate', on: :collection
    end

    # Rutas para clientes
    post 'clients/forgot_number', to: 'api/clients#forgot_number'
    put 'clients/:id/update_credit', to: 'api/clients#update_credit'

    # Versionado del motor de riesgo / crédito
    get  'risk_engine/versions', to: 'api/risk_engine_configs#index'
    post 'risk_engine/versions', to: 'api/risk_engine_configs#create'
    post 'risk_engine/versions/:version/activate', to: 'api/risk_engine_configs#activate'
  end
end
