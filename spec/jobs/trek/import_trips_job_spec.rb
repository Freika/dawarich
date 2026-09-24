# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::ImportTripsJob do
  let(:user) { create(:user) }
  let(:source) { create(:trip_source, user: user, selection_token: 'current-selection', importing: true) }

  before do
    stub_host_addresses('trek.example.test', '93.184.216.34')
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

  it 'keeps importing through a transient detail error so a retry can finish the import' do
    payload = {
      id: 12, title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      days: [], unplanned_places: [], unscheduled_reservations: [], accommodations: [], travellers: []
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(
      { status: 429 }, { status: 200, body: payload.to_json }
    )

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /429/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('429')

    described_class.new.perform(source.id, ['12'], 'current-selection')

    expect(source.reload).not_to be_importing
    expect(source.trips.find_by!(source_identifier: '12')).to be_source_active
  end

  it 'releases the import when a trip cannot be persisted, so the source can be used again' do
    payload = {
      id: 12, title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      days: [], unplanned_places: [], unscheduled_reservations: [], accommodations: [], travellers: []
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12')
      .to_return(status: 200, body: payload.to_json)
    allow_any_instance_of(Trek::Sync).to receive(:import_payload!).and_raise(ActiveRecord::RecordInvalid)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(source.reload).not_to be_importing
  end

  it 'disables the source and stops importing when TREK rejects its key during detail import' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 401)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /401/)

    expect(source.reload).to be_disabled
    expect(source).not_to be_importing
    expect(source.last_error).to include('401')
  end

  it 'keeps importing through an incomplete trip response so Active Job can retry it' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: {}.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /missing required fields/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('missing required fields')
  end

  it 'skips an undated trip and imports the remaining selection' do
    undated_payload = { id: 11, title: 'Draft', start_date: nil, end_date: nil }
    dated_payload = {
      id: 12, title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      days: [], unplanned_places: [], unscheduled_reservations: [], accommodations: [], travellers: []
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/11')
      .to_return(status: 200, body: undated_payload.to_json)
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12')
      .to_return(status: 200, body: dated_payload.to_json)

    described_class.perform_now(source.id, %w[11 12], 'current-selection')

    expect(source.reload).not_to be_importing
    expect(source.trips.find_by!(source_identifier: '12')).to be_source_active
    expect(source.last_error).to be_nil
  end

  it 'keeps importing through an invalid trip date so Active Job can retry it' do
    payload = { title: 'Tuscany', start_date: 'not a date', end_date: '2030-06-22' }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /trip start_date is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('trip start_date is invalid')
  end

  it 'keeps importing through an impossible trip date so Active Job can retry it' do
    payload = { title: 'Tuscany', start_date: '2030-02-31', end_date: '2030-06-22' }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /trip start_date is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('trip start_date is invalid')
  end

  it 'keeps importing through an inverted trip date range so Active Job can retry it' do
    payload = { title: 'Tuscany', start_date: '2030-06-22', end_date: '2030-06-14' }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /end_date precedes start_date/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('end_date precedes start_date')
  end

  it 'keeps importing through malformed nested itinerary data so Active Job can retry it' do
    payload = { title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22', days: [{}] }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /day is missing required fields/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('day is missing required fields')
  end

  it 'keeps importing through duplicate itinerary days so Active Job can retry it' do
    day = { date: '2030-06-14', day_number: 1 }
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22', days: [day, day]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /duplicate dates/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('duplicate dates')
  end

  it 'keeps importing through itinerary days outside the trip range so Active Job can retry it' do
    day = { date: '2030-06-13', day_number: 1 }
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22', days: [day]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /outside the trip range/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('outside the trip range')
  end

  it 'keeps importing through an invalid accommodation date so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      accommodations: [{ name: 'Hotel Roma', start_date: '2030-02-31' }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /accommodation start_date is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('accommodation start_date is invalid')
  end

  it 'keeps importing through invalid scheduled-place coordinates so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      days: [{ date: '2030-06-14', day_number: 1, places: [{ name: 'Uffizi', lat: 'bad', lng: 11.25 }] }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /place latitude is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('place latitude is invalid')
  end

  it 'keeps importing through invalid unplanned-place duration so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      unplanned_places: [{ name: 'Mercato Centrale', duration_minutes: 'bad' }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /unplanned place duration_minutes is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('unplanned place duration_minutes is invalid')
  end

  it 'keeps importing through invalid accommodation coordinates so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      accommodations: [{ name: 'Hotel Roma', lat: 100, lng: 11.25 }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /accommodation latitude is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('accommodation latitude is invalid')
  end

  it 'keeps importing through a fractional day number so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      days: [{ date: '2030-06-14', day_number: 1.5 }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /day number is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('day number is invalid')
  end

  it 'keeps importing through a fractional place duration so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      unplanned_places: [{ name: 'Mercato Centrale', duration_minutes: 1.5 }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /unplanned place duration_minutes is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('unplanned place duration_minutes is invalid')
  end

  it 'keeps importing through boolean coordinates so Active Job can retry it' do
    payload = {
      title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
      unplanned_places: [{ name: 'Mercato Centrale', lat: false, lng: false }]
    }
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12').to_return(status: 200, body: payload.to_json)

    expect do
      described_class.new.perform(source.id, ['12'], 'current-selection')
    end.to raise_error(Trek::Client::Error, /unplanned place latitude is invalid/)

    expect(source.reload).to be_importing
    expect(source.last_error).to include('unplanned place latitude is invalid')
  end
end
