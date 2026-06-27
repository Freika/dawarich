# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points conditional GET caching', type: :request do
  let(:user) { create(:user) }
  let(:range) { "slim=true&start_at=#{2.days.ago.to_i}&end_at=#{Time.current.to_i}" }

  before do
    create_list(:point, 3, user: user, timestamp: 1.day.ago.to_i)
  end

  it 'returns an ETag on the points index' do
    get "/api/v1/points?api_key=#{user.api_key}&#{range}"

    expect(response).to have_http_status(:ok)
    expect(response.headers['ETag']).to be_present
  end

  it 'returns 304 Not Modified when the ETag matches and data is unchanged' do
    get "/api/v1/points?api_key=#{user.api_key}&#{range}"
    etag = response.headers['ETag']

    get "/api/v1/points?api_key=#{user.api_key}&#{range}",
        headers: { 'If-None-Match' => etag }

    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end

  it 'does not run the point-row fetch on a 304 (skips serialization)' do
    get "/api/v1/points?api_key=#{user.api_key}&#{range}"
    etag = response.headers['ETag']

    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get "/api/v1/points?api_key=#{user.api_key}&#{range}",
          headers: { 'If-None-Match' => etag }
    end

    expect(response).to have_http_status(:not_modified)
    expect(queries.none? { |sql| sql.include?('ST_Y') }).to be(true)
  end

  it 'returns a fresh 200 when a new point arrives' do
    get "/api/v1/points?api_key=#{user.api_key}&#{range}"
    etag = response.headers['ETag']

    create(:point, user: user, timestamp: 1.hour.ago.to_i)

    get "/api/v1/points?api_key=#{user.api_key}&#{range}",
        headers: { 'If-None-Match' => etag }

    expect(response).to have_http_status(:ok)
  end
end
