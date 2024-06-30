# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'users', type: :request do
  # Skip this because user registration is disabled
  xdescribe 'POST /create' do
    let(:user_params) do
      { user: FactoryBot.attributes_for(:user) }
    end

    it 'creates master' do
      expect { post '/users', params: user_params }.to change(User, :count).by(1)
    end
  end
end
