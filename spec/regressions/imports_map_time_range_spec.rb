# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports map and points pages default to the import time range',
               type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }

  let!(:import) { create(:import, user: user) }

  let!(:day1_point) do
    create(:point, user: user, import: import,
                   timestamp: Time.utc(2024, 5, 1, 10, 0, 0).to_i)
  end
  let!(:day2_point) do
    create(:point, user: user, import: import,
                   timestamp: Time.utc(2024, 5, 2, 14, 0, 0).to_i)
  end

  let(:expected_start_iso) { '2024-05-01T00:00:00Z' }
  let(:expected_end_iso)   { '2024-05-02T23:59:59Z' }

  before { sign_in user }

  describe 'GET /map/v2 with only import_id' do
    it 'renders a window covering the full import range' do
      get '/map/v2', params: { import_id: import.id }

      expect(response.body).to include(%(data-maps--maplibre-start-date-value="#{expected_start_iso}"))
      expect(response.body).to include(%(data-maps--maplibre-end-date-value="#{expected_end_iso}"))
    end
  end

  describe 'GET /points with only import_id' do
    it 'renders datetime inputs covering the full import range' do
      get '/points', params: { import_id: import.id }

      expect(response.body).to match(/value="2024-05-01T00:00"[^>]*name="start_at"/)
      expect(response.body).to match(/value="2024-05-02T23:59"[^>]*name="end_at"/)
    end
  end

  describe 'GET /points without import_id and without time params' do
    it 'falls back to the last-month window' do
      get '/points'

      expected = Time.use_zone('Etc/UTC') { 1.month.ago.beginning_of_day.strftime('%Y-%m-%dT%H:%M') }
      expect(response.body).to include(%(value="#{expected}"))
    end
  end

  describe 'GET /map/v2 without import_id and without time params' do
    it 'falls back to today' do
      get '/map/v2'

      expected = Time.use_zone('Etc/UTC') { Time.zone.today.beginning_of_day.iso8601 }
      expect(response.body).to include(%(data-maps--maplibre-start-date-value="#{expected}"))
    end
  end
end
