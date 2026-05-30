# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 (maplibre)', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /map/v2 date window (C1)' do
    it 'derives the data window from ?date= when start_at/end_at are absent' do
      get map_v2_path(date: '2026-05-28', panel: 'timeline')

      expect(response).to have_http_status(:ok)
      # The top date-range form must render the requested day so the map,
      # the form, and the Timeline panel all agree (no silent desync).
      expect(response.body).to include('2026-05-28T00:00')
      expect(response.body).to include('2026-05-28T23:59')
    end

    it 'still honors explicit start_at/end_at over ?date=' do
      get map_v2_path(date: '2026-05-28', start_at: '2026-05-20T00:00', end_at: '2026-05-20T23:59')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('2026-05-20T00:00')
    end

    it 'keeps the Timeline panel open across the date-range form (preserves panel param)' do
      get map_v2_path(date: 'today', panel: 'timeline')

      expect(response.body).to include('name="panel"')
      expect(response.body).to include('value="timeline"')
    end
  end
end
