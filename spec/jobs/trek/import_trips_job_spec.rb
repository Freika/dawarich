# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::ImportTripsJob do
  let(:user) { create(:user) }
  let(:source) { create(:trip_source, user: user, selection_token: 'current-selection') }

  before do
    allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
  end

  it 'imports the selected trips and stops previously selected trips that were removed' do
    previous_trip = create(
      :trip, user: user, trip_source: source, source_identifier: 'previous', source_status: :active
    )
    payload = {
      id: 12, title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      days: [], unplanned_places: [], unscheduled_reservations: [], accommodations: [], travellers: []
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12')
      .to_return(status: 200, body: payload.to_json)

    described_class.perform_now(source.id, ['12'], 'current-selection')

    expect(source.trips.find_by!(source_identifier: '12')).to be_source_active
    expect(previous_trip.reload).to be_source_stopped
  end

  it 'does nothing when a newer selection supersedes the queued import' do
    source.update!(selection_token: 'newer-selection')

    described_class.perform_now(source.id, ['12'], 'current-selection')

    expect(a_request(:get, 'https://trek.example.test/api/v1/trips/12')).not_to have_been_made
  end
end
