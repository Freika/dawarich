# frozen_string_literal: true

require 'sidekiq/web'

Rails.application.routes.draw do
  mount ActionCable.server => '/cable'
  mount Rswag::Api::Engine => '/api-docs'
  mount Rswag::Ui::Engine => '/api-docs'

  unless DawarichSettings.self_hosted?
    Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(username),
        ::Digest::SHA256.hexdigest(ENV['SIDEKIQ_USERNAME'])
      ) &
        ActiveSupport::SecurityUtils.secure_compare(
          ::Digest::SHA256.hexdigest(password),
          ::Digest::SHA256.hexdigest(ENV['SIDEKIQ_PASSWORD'])
        )
    end
  end

  authenticate :user, lambda { |u|
    (u.admin? && DawarichSettings.self_hosted?) ||
      (u.admin? && ENV['SIDEKIQ_USERNAME'].present? && ENV['SIDEKIQ_PASSWORD'].present?)
  } do
    mount Sidekiq::Web => '/sidekiq'
  end

  authenticate :user, ->(u) { u.admin? } do
    mount Flipper::UI.app(Flipper) => '/admin/flipper'
  end
  mount RailsPulse::Engine => '/rails_pulse'

  # We want to return a nice error message if the user is not authorized to access Sidekiq
  match '/sidekiq' => redirect { |_, request|
                        request.flash[:error] = 'You are not authorized to perform this action.'
                        '/'
                      }, via: :get

  namespace :settings do
    resources :general, only: [:index]
    patch 'general', to: 'general#update'
    post 'general/verify_supporter', to: 'general#verify_supporter', as: :verify_supporter

    resources :integrations, only: [:index]
    patch 'integrations', to: 'integrations#update'

    resources :background_jobs, only: %i[index create]
    patch 'background_jobs', to: 'background_jobs#update'
    resources :users, only: %i[index show create destroy edit update] do
      member do
        post 'regenerate_api_key'
        post 'send_password_reset'
      end
      collection do
        get 'export'
        post 'import'
        patch 'update_registration_settings'
      end
    end

    resources :maps, only: %i[index]
    patch 'maps', to: 'maps#update'

    resource :two_factor, only: %i[show create destroy], controller: 'two_factor' do
      post :verify, on: :member
    end

    resource :onboarding, only: [:update] do
      post :demo_data, on: :member
      delete :demo_data, on: :member, action: :destroy_demo_data
    end
  end

  get 'settings/theme', to: 'settings#theme'
  post 'settings/generate_api_key', to: 'settings#generate_api_key', as: :generate_api_key

  get 'trial/upgrade', to: 'trial/upgrades#show', as: :trial_upgrade
  get 'trial/resume', to: 'trial/resume#show', as: :trial_resume
  get 'trial/welcome', to: 'trial/welcome#show', as: :trial_welcome

  resources :imports
  resources :visits, only: %i[index update] do
    collection do
      patch :bulk_update
    end
  end
  resources :areas, only: [:create]
  resources :places, only: %i[index destroy create update] do
    collection do
      get 'nearby'
    end
  end
  resources :exports, only: %i[index create destroy]
  resources :trips
  resources :tags, except: [:show]

  # Family management routes (only if feature is enabled)
  if DawarichSettings.family_feature_enabled?
    resource :family, only: %i[show new create edit update destroy] do
      resources :invitations, except: %i[edit update], controller: 'family/invitations'
      resources :members, only: %i[destroy], controller: 'family/memberships'
      resources :location_requests, only: %i[show create], controller: 'family/location_requests' do
        member do
          patch :accept
          patch :decline
        end
      end

      patch 'location_sharing', to: 'family/location_sharing#update', as: :location_sharing
    end

    get 'invitations/:token', to: 'family/invitations#show', as: :public_invitation
    post 'family/memberships', to: 'family/memberships#create', as: :accept_family_invitation
  end

  resources :points, only: %i[index] do
    collection do
      delete :bulk_destroy
    end
    member do
      get :address
    end
  end
  resources :notifications, only: %i[index show destroy]
  post 'notifications/mark_as_read', to: 'notifications#mark_as_read', as: :mark_notifications_as_read
  post 'notifications/destroy_all', to: 'notifications#destroy_all', as: :delete_all_notifications
  resources :stats, only: :index do
    collection do
      put :update_all
    end
  end
  resources :insights, only: :index do
    collection do
      get :details
    end
  end
  get 'stats/:year', to: 'stats#show', constraints: { year: /\d{4}/ }
  get 'stats/:year/:month', to: 'stats#month', constraints: { year: /\d{4}/, month: /(0?[1-9]|1[0-2])/ }
  put 'stats/:year/:month/update',
      to: 'stats#update',
      as: :update_year_month_stats,
      constraints: { year: /\d{4}/, month: /\d{1,2}|all/ }
  get 'shared/month/:uuid', to: 'shared/stats#show', as: :shared_stat

  # Sharing management endpoint (requires auth)
  patch 'stats/:year/:month/sharing',
        to: 'shared/stats#update',
        as: :sharing_stats,
        constraints: { year: /\d{4}/, month: /\d{1,2}/ }

  # User digests routes (yearly/monthly digest reports)
  scope module: 'users' do
    resources :digests, only: %i[index create show destroy], param: :year, as: :users_digests,
                        constraints: { year: /\d{4}/ }
  end
  get 'shared/digest/:uuid', to: 'shared/digests#show', as: :shared_users_digest
  patch 'digests/:year/sharing',
        to: 'shared/digests#update',
        as: :sharing_users_digest,
        constraints: { year: /\d{4}/ }

  root to: 'home#index'

  get 'auth/ios/success', to: 'auth/ios#success', as: :ios_success

  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions',
    omniauth_callbacks: 'users/omniauth_callbacks'
  }

  post 'users/otp_challenge', to: 'users/otp_challenge#create', as: :user_otp_challenge

  # Prometheus metrics endpoint (Yabeda + prometheus-client). Wrapped in basic auth.
  # Enablement is evaluated per-request via routing constraint, so stubbing
  # DawarichSettings.prometheus_exporter_enabled? in tests toggles 404 vs 200.
  require 'yabeda/prometheus/exporter'
  require 'dawarich/metrics_basic_auth'
  metrics_app = Dawarich::MetricsBasicAuth.new(Yabeda::Prometheus::Exporter)
  mount metrics_app,
        at: '/metrics',
        constraints: ->(_req) { DawarichSettings.prometheus_exporter_enabled? }

  # Map namespace with versioning
  namespace :map do
    get '/v1', to: 'leaflet#index', as: :v1
    get '/v2', to: 'maplibre#index', as: :v2
    resources :timeline_feeds, only: [:index] do
      get :track_info, on: :member
    end
    resource :residency, only: [:show], controller: 'residency'
  end

  # Backward compatibility redirects
  get '/map', to: 'map/leaflet#index'
  get '/maps/v2', to: redirect('/map/v2')

  namespace :api do
    namespace :v1 do
      get   'photos', to: 'photos#index'
      get   'health', to: 'health#index'
      patch 'settings', to: 'settings#update'
      get   'settings', to: 'settings#index'
      get   'settings/transportation_recalculation_status', to: 'settings#transportation_recalculation_status'
      get   'users/me', to: 'users#me'

      resources :areas,     only: %i[index show create update destroy]
      resources :imports,   only: %i[index show create]
      resources :places,    only: %i[index show create update destroy] do
        collection do
          get 'nearby'
        end
      end
      resources :locations, only: %i[index] do
        collection do
          get 'suggestions'
        end
      end
      resources :points, only: %i[index create update destroy] do
        collection do
          delete :bulk_destroy
        end
      end
      resources :visits, only: %i[index show create update destroy] do
        get 'possible_places', to: 'visits/possible_places#index', on: :member
        collection do
          post 'merge', to: 'visits#merge'
          post 'bulk_update', to: 'visits#bulk_update'
        end
      end
      resource :plan, only: [:show], controller: 'plan'
      resource :residency, only: [:show], controller: 'residency'
      resources :stats, only: :index
      resources :insights, only: :index do
        collection do
          get :details
        end
      end
      resources :digests, only: %i[index show create destroy], param: :year,
                          constraints: { year: /\d{4}/ }
      resources :tags, only: [] do
        collection do
          get 'privacy_zones'
        end
      end

      namespace :overland do
        resources :batches, only: :create
      end

      namespace :owntracks do
        resources :points, only: :create
      end

      namespace :countries do
        resources :borders, only: :index
        resources :visited_cities, only: :index
      end

      namespace :points do
        get 'tracked_months', to: 'tracked_months#index'
      end

      resources :photos, only: %i[index] do
        member do
          get 'thumbnail', constraints: { id: %r{[^/]+} }
        end
      end

      resources :tracks, only: %i[index show] do
        resources :points, only: [:index], controller: 'tracks/points'
      end

      resources :timeline, only: [:index]

      namespace :maps do
        resources :hexagons, only: [:index] do
          collection do
            get :bounds
          end
        end
      end

      namespace :immich do
        post 'enrich/scan', to: 'enrich#scan'
        post 'enrich', to: 'enrich#create'
      end

      namespace :families do
        resources :locations, only: [:index] do
          collection do
            get :history
          end
        end
      end

      post 'subscriptions/callback', to: 'subscriptions#callback'
    end
  end
end
