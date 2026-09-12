# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::Sync do
  let(:user) { create(:user) }
  let(:source) { create(:trip_source, user: user) }

  let(:payload) do
    {
      id: 12,
      title: 'Tuscany',
      description: 'Wine and hill towns',
      start_date: '2030-06-14',
      end_date: '2030-06-22',
      days: [
        {
          date: '2030-06-14', day_number: 1, title: 'Arrival', notes: 'Check the rental car',
          places: [
            {
              name: 'Uffizi', address: 'Florence', lat: 43.76, lng: 11.25, time: '14:00',
              end_time: nil, duration_minutes: 180, category: 'Museum', notes: 'Tickets ready',
              transport_mode: 'walking'
            }
          ],
          day_notes: [{ text: 'Bring the tickets', time: '09:00' }],
          reservations: [
            {
              type: 'flight', title: 'LH 1234', location: 'FRA', time: '2030-06-14T08:00:00',
              end_time: nil, status: 'confirmed', notes: nil
            }
          ]
        }
      ],
      unplanned_places: [], unscheduled_reservations: [],
      accommodations: [
        {
          name: 'Hotel Alba', address: nil, lat: nil, lng: nil, start_date: '2030-06-14',
          end_date: '2030-06-15', check_in: '15:00', check_out: '11:00', notes: nil
        }
      ],
      travellers: [{ name: 'ada', owner: true }, { name: 'bob', owner: false }]
    }
  end

  before do
    allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
  end

  describe '#import!' do
    it 'creates a managed future trip and its complete source-owned itinerary' do
      stub_trip(payload)

      expect do
        @trip, @created, @changed = described_class.new(source).import!('12')
      end.not_to have_enqueued_job(Trips::CalculateAllJob)

      expect(@created).to be(true)
      expect(@changed).to be(true)
      expect(@trip).to have_attributes(name: 'Tuscany', source_identifier: '12', source_status: 'active')
      expect(@trip.user).to eq(user)
      expect(@trip.planned_days.size).to eq(1)
      expect(@trip.planned_days.first.planned_stops.first).to have_attributes(name: 'Uffizi', transport_mode: 'walking')
      expect(@trip.planned_days.first.planned_day_notes.first.body).to eq('Bring the tickets')
      expect(@trip.planned_reservations.first.title).to eq('LH 1234')
      expect(@trip.planned_accommodations.first.name).to eq('Hotel Alba')
      expect(@trip.planned_travellers.pluck(:name)).to contain_exactly('ada', 'bob')
      expect(@trip.notes).to be_empty
    end

    it 'does not rewrite source-owned rows when the normalized snapshot is unchanged' do
      stub_trip(payload)
      trip, = described_class.new(source).import!('12')
      original_stop_id = trip.planned_days.first.planned_stops.first.id

      stub_trip(payload)
      _, created, changed = described_class.new(source).import!('12')

      expect(created).to be(false)
      expect(changed).to be(false)
      expect(trip.reload.planned_days.first.planned_stops.first.id).to eq(original_stop_id)
    end
  end

  describe '#call' do
    it 'stops, but does not delete, a selected trip that TREK archives' do
      stub_trip(payload)
      trip, = described_class.new(source).import!('12')

      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_return(status: 200, body: { trips: [{ id: 12, archived: true }] }.to_json)

      result = described_class.new(source).call

      expect(result.stopped).to eq(1)
      expect(trip.reload).to be_source_stopped
      expect(trip.planned_days).not_to be_empty
    end

    it 'disables the source when TREK rejects the key' do
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_return(status: 401, body: { error: 'unknown key' }.to_json)

      expect { described_class.new(source).call }.to raise_error(Trek::Client::Error)

      expect(source.reload).to be_disabled
      expect(source.last_error).to include('401')
    end
  end

  def stub_trip(body)
    stub_request(:get, 'https://trek.example.test/api/v1/trips/12')
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end
end
