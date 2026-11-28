# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Arrival time for a visit spanning the next full day', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:arrival_place) do
    create(:place, user: user, name: 'Synthetic ocean arrival', latitude: -40.12345, longitude: -140.12345)
  end
  let!(:overnight_visit) do
    create(:visit, user: user, place: arrival_place, name: 'Synthetic long stay', status: :confirmed,
                   started_at: Time.utc(2026, 10, 20, 18, 45), ended_at: Time.utc(2026, 10, 22, 8),
                   duration: 2235)
  end

  before do
    earlier_place = create(:place, user: user, name: 'Synthetic ocean departure',
                                   latitude: -40.22345, longitude: -140.22345)
    create(:visit, user: user, place: earlier_place, name: 'Synthetic earlier stop', status: :confirmed,
                   started_at: Time.utc(2026, 10, 20, 9), ended_at: Time.utc(2026, 10, 20, 10),
                   duration: 60)
    sign_in user
  end

  it 'keeps All day on the full day and shows the arrival clock when navigating to the preceding day' do
    get map_timeline_feeds_path(start_at: '2026-10-21T00:00:00Z', end_at: '2026-10-21T23:59:59Z')

    expect(response).to have_http_status(:ok)
    full_day = Nokogiri::HTML(response.body)
    expect(full_day.css("#visit_entry_#{overnight_visit.id} .visit-row__all-day")).to be_present

    get map_timeline_feeds_path(start_at: '2026-10-20T00:00:00Z', end_at: '2026-10-20T23:59:59Z')

    expect(response).to have_http_status(:ok)
    arrival_day = Nokogiri::HTML(response.body)
    expect(arrival_day.css('[data-testid="visit-row"]').size).to eq(2)
    expect(arrival_day.css("#visit_entry_#{overnight_visit.id} .visit-row__time").text.squish).to eq('18:45')
  end
end
