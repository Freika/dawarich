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

  # We want to return a nice error message if the user is not authorized to access Sidekiq
  match '/sidekiq' => redirect { |_, request|
                        request.flash[:error] = 'You are not authorized to perform this action.'
                        '/'
                      }, via: :get

  resources :settings, only: :index
  namespace :settings do
    resources :background_jobs, only: %i[index create]
    resources :users, only: %i[index create destroy edit update] do
      collection do
        get 'export'
        post 'import'
      end
    end

    resources :maps, only: %i[index]
    patch 'maps', to: 'maps#update'
  end

  patch 'settings', to: 'settings#update'
  get 'settings/theme', to: 'settings#theme'
  post 'settings/generate_api_key', to: 'settings#generate_api_key', as: :generate_api_key

  resources :imports
  resources :visits, only: %i[index update]
  resources :places, only: %i[index destroy]
  resources :exports, only: %i[index create destroy]
  resources :trips

  # Family management routes (only if feature is enabled)
  if DawarichSettings.family_feature_enabled?
    resource :family, only: %i[show new create edit update destroy] do
      patch :update_location_sharing, on: :member

      resources :invitations, except: %i[edit update], controller: 'family/invitations'
      resources :members, only: %i[destroy], controller: 'family/memberships'
    end

    get 'invitations/:token', to: 'family/invitations#show', as: :public_invitation
    post 'family/memberships', to: 'family/memberships#create', as: :accept_family_invitation
  end

  resources :points, only: %i[index] do
    collection do
      delete :bulk_destroy
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

  root to: 'home#index'

  get 'auth/ios/success', to: 'auth/ios#success', as: :ios_success

  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions'
  }

  resources :metrics, only: [:index]

  get 'map', to: 'map#index'

  namespace :api do
    namespace :v1 do
      get   'photos', to: 'photos#index'
      get   'health', to: 'health#index'
      patch 'settings', to: 'settings#update'
      get   'settings', to: 'settings#index'
      get   'users/me', to: 'users#me'

      resources :areas,     only: %i[index create update destroy]
      resources :locations, only: %i[index] do
        collection do
          get 'suggestions'
        end
      end
      resources :points,    only: %i[index create update destroy]
      resources :visits,    only: %i[index create update destroy] do
        get 'possible_places', to: 'visits/possible_places#index', on: :member
        collection do
          post 'merge', to: 'visits#merge'
          post 'bulk_update', to: 'visits#bulk_update'
        end
      end
      resources :stats, only: :index

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

      namespace :maps do
        resources :tile_usage, only: [:create]
        resources :hexagons, only: [:index] do
          collection do
            get :bounds
          end
        end
      end

      resources :families, only: [] do
        collection do
          get :locations
        end
      end

      post 'subscriptions/callback', to: 'subscriptions#callback'
    end
  end
end
