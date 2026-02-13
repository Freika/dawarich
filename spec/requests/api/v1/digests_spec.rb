# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Digests', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  describe 'GET /api/v1/digests' do
    let!(:recent_digest) { create(:users_digest, year: 2024, user: user) }
    let!(:older_digest) { create(:users_digest, year: 2023, user: user) }
    let!(:available_stat) { create(:stat, year: 2022, month: 1, user: user) }

    it 'returns http unauthorized without api key' do
      get api_v1_digests_url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns list of digests and available years' do
      get api_v1_digests_url, headers: headers

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['digests']).to be_an(Array)
      expect(json['digests'].length).to eq(2)
      expect(json['digests'].first['year']).to eq(2024)
      expect(json['digests'].first['distance']).to eq(500_000)
      expect(json['digests'].first['countriesCount']).to eq(3)
      expect(json['digests'].first['citiesCount']).to eq(5)
      expect(json['digests'].first['createdAt']).to be_present
      expect(json['availableYears']).to include(2022)
      expect(json['availableYears']).not_to include(2024)
      expect(json['availableYears']).not_to include(2023)
    end
  end

  describe 'GET /api/v1/digests/:year' do
    let!(:digest) { create(:users_digest, year: 2024, user: user) }

    it 'returns http unauthorized without api key' do
      get api_v1_digest_url(year: 2024)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns full digest detail' do
      get api_v1_digest_url(year: 2024), headers: headers

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['year']).to eq(2024)
      expect(json['distance']).to be_a(Hash)
      expect(json['distance']['meters']).to eq(500_000)
      expect(json['distance']['comparisonText']).to be_present
      expect(json['toponyms']).to be_a(Hash)
      expect(json['toponyms']['countriesCount']).to eq(3)
      expect(json['toponyms']['citiesCount']).to eq(5)
      expect(json['toponyms']['countries']).to be_an(Array)
      expect(json['monthlyDistances']).to be_present
      expect(json['timeSpentByLocation']).to be_present
      expect(json['firstTimeVisits']).to be_present
      expect(json['yearOverYear']).to be_a(Hash)
      expect(json['yearOverYear']['distanceChangePercent']).to be_present
      expect(json['allTimeStats']).to be_a(Hash)
      expect(json['allTimeStats']['totalCountries']).to eq(10)
      expect(json['travelPatterns']).to be_a(Hash)
      expect(json['createdAt']).to be_present
      expect(json['updatedAt']).to be_present
    end

    it 'returns 404 for non-existent digest year' do
      get api_v1_digest_url(year: 1999), headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'sets Cache-Control header' do
      get api_v1_digest_url(year: 2024), headers: headers

      expect(response.headers['Cache-Control']).to include('max-age=3600')
      expect(response.headers['Cache-Control']).to include('private')
    end

    it 'returns Last-Modified header' do
      get api_v1_digest_url(year: 2024), headers: headers

      expect(response.headers['Last-Modified']).to be_present
    end

    it 'returns 304 Not Modified when content has not changed' do
      get api_v1_digest_url(year: 2024), headers: headers
      last_modified = response.headers['Last-Modified']

      get api_v1_digest_url(year: 2024),
          headers: headers.merge('If-Modified-Since' => last_modified)

      expect(response).to have_http_status(:not_modified)
    end
  end

  describe 'POST /api/v1/digests' do
    let!(:stat) { create(:stat, year: 2024, month: 1, user: user) }

    it 'returns http unauthorized without api key' do
      post api_v1_digests_url, params: { year: 2024 }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for inactive user' do
      inactive_user = create(:user)
      inactive_user.update_columns(status: 'inactive', active_until: 1.day.ago)
      create(:stat, year: 2024, month: 1, user: inactive_user)

      post api_v1_digests_url,
           headers: { 'Authorization' => "Bearer #{inactive_user.api_key}" },
           params: { year: 2024 }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'enqueues digest calculation job and returns 202' do
      expect do
        post api_v1_digests_url, headers: headers, params: { year: 2024 }
      end.to have_enqueued_job(Users::Digests::CalculatingJob).with(user.id, 2024)

      expect(response).to have_http_status(:accepted)

      json = JSON.parse(response.body)
      expect(json['message']).to include('2024')
    end

    it 'returns 422 for invalid year' do
      post api_v1_digests_url, headers: headers, params: { year: 1800 }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 for year with no stats' do
      post api_v1_digests_url, headers: headers, params: { year: 2020 }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/digests/:year' do
    let!(:digest) { create(:users_digest, year: 2024, user: user) }

    it 'returns http unauthorized without api key' do
      delete api_v1_digest_url(year: 2024)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'destroys the digest and returns 204' do
      expect do
        delete api_v1_digest_url(year: 2024), headers: headers
      end.to change(Users::Digest, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'returns 404 for non-existent digest year' do
      delete api_v1_digest_url(year: 1999), headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
