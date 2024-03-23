Rails.application.routes.draw do
  resources :imports
  resources :stats, only: :index

  root to: 'home#index'
  devise_for :users

  get 'points', to: 'points#index'

  namespace :api do
    namespace :v1 do
      resources :points
    end
  end
end
