# frozen_string_literal: true

require 'sidekiq/web'

Rails.application.routes.draw do
  mount Rswag::Api::Engine => '/api-docs'
  mount Rswag::Ui::Engine => '/api-docs'
  authenticate :user, ->(u) { u.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end

  # We want to return a nice error message if the user is not authorized to access Sidekiq
  match '/sidekiq' => redirect { |_, request|
                        request.flash[:error] = 'You are not authorized to perform this action.'
                        '/'
                      }, via: :get

  resources :settings, only: :index
  namespace :settings do
    resources :background_jobs, only: %i[index create destroy]
    resources :users, only: :create
  end

  patch 'settings', to: 'settings#update'
  get 'settings/theme', to: 'settings#theme'
  post 'settings/generate_api_key', to: 'settings#generate_api_key', as: :generate_api_key

  resources :imports
  resources :exports, only: %i[index create destroy]
  resources :points, only: %i[index] do
    collection do
      delete :bulk_destroy
    end
  end
  resources :notifications, only: %i[index show destroy]
  post 'notifications/mark_as_read', to: 'notifications#mark_as_read', as: :mark_notifications_as_read
  resources :stats, only: :index do
    collection do
      post :update
    end
  end
  get 'stats/:year', to: 'stats#show', constraints: { year: /\d{4}/ }

  root to: 'home#index'
  devise_for :users, skip: [:registrations]
  as :user do
    get 'users/edit' => 'devise/registrations#edit', :as => 'edit_user_registration'
    put 'users' => 'devise/registrations#update', :as => 'user_registration'
  end

  # And then modify the app/views/devise/shared/_links.erb

  get 'map', to: 'map#index'

  namespace :api do
    namespace :v1 do
      namespace :overland do
        resources :batches, only: :create
      end

      namespace :owntracks do
        resources :points, only: :create
      end
    end
  end
end
