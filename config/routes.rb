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

    resources :products, controller: 'api/products' do
      post 'manage_collection', on: :collection
      post 'import_search', on: :collection
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
    end

    get 'current_user', to: 'api/users#current_user'

    resources :exchange_rates, controller: 'api/exchange_rates', only: [:index, :show, :create, :destroy] do
      post 'refresh', on: :collection
    end

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

    post 'clients/forgot_number', to: 'api/clients#forgot_number'
    put 'clients/:id/update_credit', to: 'api/clients#update_credit'

    get  'risk_engine/versions', to: 'api/risk_engine_configs#index'
    post 'risk_engine/versions', to: 'api/risk_engine_configs#create'
    post 'risk_engine/versions/:version/activate', to: 'api/risk_engine_configs#activate'
  end
end
