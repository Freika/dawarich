# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API key authentication', type: :request do
  let!(:user_without_key) { create(:user).tap { |user| user.update_column(:api_key, '') } }

  it 'refuses an empty api_key parameter even when a user has no key' do
    get '/api/v1/points', params: { api_key: '' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers an unauthenticated health probe without looking up a user' do
    user_queries = []
    collect = ->(*, payload) { user_queries << payload[:sql] if payload[:sql].match?(/\busers\b/) }

    ActiveSupport::Notifications.subscribed(collect, 'sql.active_record') { get '/api/v1/health' }

    expect(response).to have_http_status(:success)
    expect(user_queries).to be_empty
  end
end
