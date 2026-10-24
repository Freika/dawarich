# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Date and time preferences per request', type: :controller do
  let(:user) do
    create(:user, settings: { 'date_format' => 'yyyy-mm-dd', 'time_format' => '12h', 'first_day_of_week' => 'sunday' })
  end

  describe ApplicationController do
    controller do
      def index
        render plain: Current.date_time_preferences.cache_key
      end
    end

    before { routes.draw { get 'index' => 'anonymous#index' } }

    it "applies the signed-in user's preferences" do
      sign_in user

      get :index

      expect(response.body).to eq('yyyy-mm-dd-12h-sunday')
    end

    it 'uses the defaults for anonymous visitors' do
      get :index

      expect(response.body).to eq('auto-auto-monday')
    end

    it 'does not keep the preferences after the request' do
      sign_in user

      get :index

      expect(Current.date_time_preferences).to eq(Users::DateTimePreferences::DEFAULT)
    end
  end

  describe ApiController do
    controller do
      def index
        render plain: Current.date_time_preferences.cache_key
      end
    end

    before do
      routes.draw do
        devise_for :users
        get 'index' => 'anonymous#index'
        get 'index' => 'api#index'
      end
    end

    it 'always uses the defaults for API requests' do
      sign_in user

      get :index, params: { api_key: user.api_key }

      expect(response.body).to eq('auto-auto-monday')
    end
  end

  describe Shared::StatsController do
    controller(Shared::StatsController) do
      def index
        render plain: Current.date_time_preferences.cache_key
      end
    end

    before { routes.draw { get 'index' => 'shared/stats#index' } }

    it 'uses the defaults on public pages even for the signed-in owner' do
      sign_in user

      get :index

      expect(response.body).to eq('auto-auto-monday')
    end
  end
end
