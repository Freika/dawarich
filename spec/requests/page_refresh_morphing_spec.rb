# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Page refresh morphing', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'controllers that opt in' do
    it 'asks Turbo to morph the imports index' do
      get imports_path

      expect(response.body).to include('name="turbo-refresh-method" content="morph"')
      expect(response.body).to include('name="turbo-refresh-scroll" content="preserve"')
    end

    it 'asks Turbo to morph the notifications index' do
      get notifications_path

      expect(response.body).to include('name="turbo-refresh-method" content="morph"')
    end

    it 'asks Turbo to morph the general settings page' do
      get settings_general_index_path

      expect(response.body).to include('name="turbo-refresh-method" content="morph"')
    end
  end

  describe 'controllers that stay on replace' do
    it 'leaves the chart-bearing stats index alone' do
      get stats_path

      expect(response.body).not_to include('turbo-refresh-method')
    end

    it 'leaves the map alone' do
      get map_path

      expect(response.body).not_to include('turbo-refresh-method')
    end
  end
end
