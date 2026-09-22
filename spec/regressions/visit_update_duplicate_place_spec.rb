# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Updating a visit to a duplicate place', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
  let(:place) { create(:place, user: user, name: 'Coffee Shop') }
  let(:started_at) { Time.zone.parse('2026-09-01 10:00:00') }
  let!(:existing_visit) do
    create(:visit, user: user, place: place, started_at: started_at,
                   ended_at: started_at + 30.minutes, status: :confirmed)
  end
  let!(:visit) do
    create(:visit, user: user, place: nil, started_at: started_at,
                   ended_at: started_at + 20.minutes, status: :suggested)
  end
  let(:auth_headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  it 'returns a validation response without changing either visit' do
    patch "/api/v1/visits/#{visit.id}",
          params: { visit: { place_id: place.id } },
          headers: auth_headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch('error')).to eq('A visit already exists for this place and start time')
    expect(response.parsed_body.fetch('code')).to eq('duplicate_place_start')
    expect(visit.reload).to have_attributes(place_id: nil, status: 'suggested')
    expect(existing_visit.reload).to have_attributes(place_id: place.id, status: 'confirmed')
  end

  it 'returns the same response when the database detects a concurrent collision' do
    visit_id = visit.id
    allow_any_instance_of(Visit).to receive(:save).and_raise(
      ActiveRecord::RecordNotUnique,
      "duplicate key violates #{Visit::DUPLICATE_PLACE_START_INDEX}"
    )

    patch "/api/v1/visits/#{visit_id}",
          params: { visit: { place_id: place.id } },
          headers: auth_headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch('error')).to eq('A visit already exists for this place and start time')
    expect(response.parsed_body.fetch('code')).to eq('duplicate_place_start')
  end

  it 'answers in English for a German user with a German Accept-Language header' do
    user.update!(settings: user.settings.merge('locale' => 'de'))

    patch "/api/v1/visits/#{visit.id}",
          params: { visit: { place_id: place.id } },
          headers: auth_headers.merge('Accept-Language' => 'de-DE,de;q=0.9')

    expect(response.parsed_body.fetch('error')).to eq('A visit already exists for this place and start time')
  end
end
