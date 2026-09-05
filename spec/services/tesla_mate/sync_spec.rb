# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::Sync do
  include ActiveSupport::Testing::TimeHelpers

  let(:base_url) { 'https://teslamate.example' }
  let(:user) do
    create(:user).tap do |record|
      record.update!(settings: record.settings.merge('teslamate_url' => base_url))
    end
  end

  it 'imports completed-drive positions for every car with normalized units and idempotent intake' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }, { car_id: 2 }] } }.to_json)

    stub_drives(car_id: 1, drive_id: 11, unit: 'km')
    stub_drives(car_id: 2, drive_id: 22, unit: 'mi')
    stub_drive(car_id: 1, drive_id: 11, unit: 'km', detail: {
                 detail_id: 111, date: '2026-09-01T10:00:00+02:00',
                 latitude: 52.52, longitude: 13.405, speed: 36,
                 elevation: 34.5, battery_level: 81, usable_battery_level: 80
               })
    stub_drive(car_id: 2, drive_id: 22, unit: 'mi', detail: {
                 detail_id: 222, date: '2026-09-01T11:00:00+02:00',
                 latitude: 48.137, longitude: 11.575, speed: 10,
                 elevation: nil, battery_level: 70, usable_battery_level: nil
               })

    travel_to(Time.zone.parse('2026-09-02 12:00:00 UTC')) do
      expect { described_class.new(user).call }.to change { user.points.count }.by(2)
      expect { described_class.new(user).call }.not_to(change { user.points.count })
    end

    metric = user.points.find_by!(tracker_id: 'teslamate-car-1')
    expect(metric.timestamp).to eq(Time.iso8601('2026-09-01T10:00:00+02:00').to_i)
    expect(metric.lon).to be_within(0.000_001).of(13.405)
    expect(metric.lat).to be_within(0.000_001).of(52.52)
    expect(metric.velocity.to_f).to be_within(0.000_001).of(10.0)
    expect(metric.altitude.to_f).to eq(34.5)
    expect(metric.battery).to eq(80)
    expect(metric.external_track_id).to eq('teslamate-drive-11')
    expect(metric.raw_data).to include('teslamate_car_id' => 1, 'teslamate_drive_id' => 11,
                                       'teslamate_detail_id' => 111)

    imperial = user.points.find_by!(tracker_id: 'teslamate-car-2')
    expect(imperial.velocity.to_f).to be_within(0.000_001).of(4.4704)
    expect(imperial.battery).to eq(70)
    expect(user.reload.settings).to include(
      'teslamate_last_synced_at' => '2026-09-02T12:00:00Z',
      'teslamate_last_synced_url' => base_url
    )
  end

  it 'keeps successful drive points but withholds the checkpoint when another drive fails' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_request(:get, %r{#{base_url}/api/v1/cars/1/drives})
      .to_return(status: 200, body: {
        data: { drives: [{ drive_id: 11 }, { drive_id: 12 }], units: { unit_of_length: 'km' } }
      }.to_json)
    stub_drive(car_id: 1, drive_id: 11, unit: 'km', detail: {
                 detail_id: 111, date: '2026-09-01T10:00:00Z',
                 latitude: 52.52, longitude: 13.405, speed: 0
               })
    stub_request(:get, "#{base_url}/api/v1/cars/1/drives/12")
      .to_return(status: 200, body: { error: 'No rows were returned!' }.to_json)

    expect { described_class.new(user).call }
      .to raise_error(TeslaMate::Sync::IncompleteError, /drive 12.*No rows/)

    expect(user.points.count).to eq(1)
    expect(user.reload.settings['teslamate_last_synced_at']).to be_nil
  end

  it 'paginates completed drives until a short page is returned' do
    first_page = Array.new(100) { |index| { drive_id: index + 1 } }
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_request(:get, %r{#{base_url}/api/v1/cars/1/drives\?})
      .with(query: hash_including('page' => '1', 'show' => '100'))
      .to_return(status: 200, body: {
        data: { drives: first_page, units: { unit_of_length: 'km' } }
      }.to_json)
    second_page = stub_request(:get, "#{base_url}/api/v1/cars/1/drives")
                  .with(query: hash_including('page' => '2', 'show' => '100'))
                  .to_return(status: 200, body: {
                    data: { drives: [{ drive_id: 101 }], units: { unit_of_length: 'km' } }
                  }.to_json)
    stub_request(:get, %r{#{base_url}/api/v1/cars/1/drives/\d+})
      .to_return(status: 200, body: {
        data: { drive: { drive_details: [] }, units: { unit_of_length: 'km' } }
      }.to_json)

    described_class.new(user).call

    expect(second_page).to have_been_requested.once
  end

  it 'overlaps the prior checkpoint while freezing the new sync cutoff' do
    user.update!(settings: user.settings.merge(
      'teslamate_last_synced_at' => '2026-09-01T12:00:00Z',
      'teslamate_last_synced_url' => base_url
    ))
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    query = {
      'page' => '1', 'show' => '100',
      'startDate' => '2026-08-25T12:00:00Z',
      'endDate' => '2026-09-02T12:00:00Z'
    }
    drive_page = stub_request(:get, "#{base_url}/api/v1/cars/1/drives")
                 .with(query: query)
                 .to_return(status: 200, body: { data: { drives: nil } }.to_json)

    travel_to(Time.zone.parse('2026-09-02 12:00:00 UTC')) { described_class.new(user).call }

    expect(drive_page).to have_been_requested.once
  end

  it 'ignores a checkpoint from another TeslaMateApi source' do
    user.update!(settings: user.settings.merge(
      'teslamate_last_synced_at' => '2026-09-01T12:00:00Z',
      'teslamate_last_synced_url' => 'https://teslamate-old.example'
    ))
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    drive_page = stub_request(:get, "#{base_url}/api/v1/cars/1/drives")
                 .with(
                   query: {
                     'page' => '1', 'show' => '100',
                     'endDate' => '2026-09-02T12:00:00Z'
                   }
                 )
                 .to_return(status: 200, body: { data: { drives: nil } }.to_json)

    travel_to(Time.zone.parse('2026-09-02 12:00:00 UTC')) { described_class.new(user).call }

    expect(drive_page).to have_been_requested.once
    expect(user.reload.settings['teslamate_last_synced_url']).to eq(base_url)
  end

  it 'does not write an old source checkpoint after the URL changes during a sync' do
    new_url = 'https://teslamate-new.example'
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_request(:get, %r{#{base_url}/api/v1/cars/1/drives\?})
      .to_return do
        user.reload.update!(settings: user.settings.merge('teslamate_url' => new_url))
        { status: 200, body: { data: { drives: nil } }.to_json }
      end

    described_class.new(user).call

    expect(user.reload.settings['teslamate_url']).to eq(new_url)
    expect(user.settings['teslamate_last_synced_at']).to be_nil
    expect(user.settings['teslamate_last_synced_url']).to be_nil
  end

  it 'coalesces historical follow-up work without broadcasting imported positions' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_request(:get, %r{#{base_url}/api/v1/cars/1/drives\?})
      .to_return(status: 200, body: {
        data: { drives: [{ drive_id: 11 }, { drive_id: 12 }], units: { unit_of_length: 'km' } }
      }.to_json)
    stub_drive(car_id: 1, drive_id: 11, unit: 'km', detail: {
                 detail_id: 111, date: '2026-09-01T10:00:00Z',
                 latitude: 52.52, longitude: 13.405, speed: 10
               })
    stub_drive(car_id: 1, drive_id: 12, unit: 'km', detail: {
                 detail_id: 112, date: '2026-09-01T11:00:00Z',
                 latitude: 52.53, longitude: 13.415, speed: 20
               })
    realtime = instance_double(Tracks::RealtimeDebouncer, trigger: nil)
    backfill = instance_double(Tracks::BackfillScheduler, call: nil)
    allow(Tracks::RealtimeDebouncer).to receive(:new).with(user.id).and_return(realtime)
    allow(Tracks::BackfillScheduler).to receive(:new).with(
      user.id,
      [Time.iso8601('2026-09-01T10:00:00Z').to_i, Time.iso8601('2026-09-01T11:00:00Z').to_i]
    ).and_return(backfill)
    allow(Points::LiveBroadcaster).to receive(:new)
    allow(Visits::RealtimeDebouncer).to receive(:new)

    expect { described_class.new(user).call }
      .to have_enqueued_job(Points::AnomalyFilterJob)
      .with(user.id, Time.iso8601('2026-09-01T10:00:00Z').to_i,
            Time.iso8601('2026-09-01T11:00:00Z').to_i)
      .exactly(:once)

    expect(Tracks::RealtimeDebouncer).to have_received(:new).once
    expect(Tracks::BackfillScheduler).to have_received(:new).once
    expect(Points::LiveBroadcaster).not_to have_received(:new)
    expect(Visits::RealtimeDebouncer).not_to have_received(:new)
  end

  it 'replays historical processing after an interruption that follows point persistence' do
    timestamp = Time.iso8601('2026-09-01T10:00:00Z').to_i
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_drives(car_id: 1, drive_id: 11, unit: 'km')
    stub_drive(car_id: 1, drive_id: 11, unit: 'km', detail: {
                 detail_id: 111, date: '2026-09-01T10:00:00Z',
                 latitude: 52.52, longitude: 13.405, speed: 10
               })
    interrupted = instance_double(Tracks::RealtimeDebouncer)
    recovered = instance_double(Tracks::RealtimeDebouncer, trigger: nil)
    allow(interrupted).to receive(:trigger).and_raise('redis unavailable')
    allow(Tracks::RealtimeDebouncer).to receive(:new).with(user.id).and_return(interrupted, recovered)
    backfill = instance_double(Tracks::BackfillScheduler, call: nil)
    allow(Tracks::BackfillScheduler).to receive(:new).with(user.id, [timestamp, timestamp]).and_return(backfill)

    expect { described_class.new(user).call }.to raise_error('redis unavailable')

    expect(user.points.count).to eq(1)
    expect(user.reload.settings).to include(
      'teslamate_processing_pending' => true,
      'teslamate_processing_pending_url' => base_url
    )

    clear_enqueued_jobs
    expect { described_class.new(user.reload).call }
      .to have_enqueued_job(Points::AnomalyFilterJob).with(user.id, timestamp, timestamp)

    expect(Tracks::BackfillScheduler).to have_received(:new).once
    expect(user.reload.settings).to include(
      'teslamate_processing_pending' => false,
      'teslamate_processing_pending_url' => nil,
      'teslamate_last_synced_url' => base_url
    )
  end

  it 'retains recovery state when intake fails after persisting points' do
    timestamp = Time.iso8601('2026-09-01T10:00:00Z').to_i
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_drives(car_id: 1, drive_id: 11, unit: 'km')
    stub_drive(car_id: 1, drive_id: 11, unit: 'km', detail: {
                 detail_id: 111, date: '2026-09-01T10:00:00Z',
                 latitude: 52.52, longitude: 13.405, speed: 10
               })
    intake_calls = 0
    allow(Points::Intake).to receive(:call).and_wrap_original do |original, **arguments|
      rows = original.call(**arguments)
      intake_calls += 1
      raise 'counter update failed' if intake_calls == 1

      rows
    end
    backfill = instance_double(Tracks::BackfillScheduler, call: nil)
    allow(Tracks::RealtimeDebouncer).to receive(:new)
      .with(user.id).and_return(instance_double(Tracks::RealtimeDebouncer, trigger: nil))
    allow(Tracks::BackfillScheduler).to receive(:new).with(user.id, [timestamp, timestamp]).and_return(backfill)

    expect { described_class.new(user).call }.to raise_error('counter update failed')

    expect(user.points.count).to eq(1)
    expect(user.reload.settings).to include(
      'teslamate_processing_pending' => true,
      'teslamate_processing_pending_url' => base_url
    )

    expect { described_class.new(user.reload).call }
      .to have_enqueued_job(Points::AnomalyFilterJob).with(user.id, timestamp, timestamp)

    expect(Tracks::BackfillScheduler).to have_received(:new).once
    expect(user.reload.settings).to include(
      'teslamate_processing_pending' => false,
      'teslamate_processing_pending_url' => nil,
      'teslamate_last_synced_url' => base_url
    )
  end

  it 'stops fetching drive details after the operation failure budget is spent' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_request(:get, %r{#{base_url}/api/v1/cars/1/drives\?})
      .to_return(status: 200, body: {
        data: { drives: (1..5).map { |drive_id| { drive_id: drive_id } },
                units: { unit_of_length: 'km' } }
      }.to_json)
    requests = (1..5).index_with do |drive_id|
      stub_request(:get, "#{base_url}/api/v1/cars/1/drives/#{drive_id}")
        .to_return(status: 200, body: { error: 'database unavailable' }.to_json)
    end

    expect { described_class.new(user).call }
      .to raise_error(TeslaMate::Sync::IncompleteError, /drive 3/)

    expect(requests.fetch(1)).to have_been_requested.once
    expect(requests.fetch(2)).to have_been_requested.once
    expect(requests.fetch(3)).to have_been_requested.once
    expect(requests.fetch(4)).not_to have_been_requested
    expect(requests.fetch(5)).not_to have_been_requested
  end

  it 'skips malformed position rows without discarding valid rows from the drive' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_drives(car_id: 1, drive_id: 11, unit: 'km')
    stub_request(:get, "#{base_url}/api/v1/cars/1/drives/11")
      .to_return(status: 200, body: {
        data: {
          drive: { drive_details: [
            'bad-row',
            { detail_id: 1, date: 'not-a-date', latitude: 52.52, longitude: 13.405 },
            { detail_id: 2, date: '2026-09-01T10:00:00Z', latitude: 91, longitude: 13.405 },
            { detail_id: 3, date: '2026-09-01T10:01:00Z', latitude: 52.52, longitude: 13.405 }
          ] },
          units: { unit_of_length: 'km' }
        }
      }.to_json)

    result = described_class.new(user).call

    expect(result).to include(points: 1, skipped_points: 3)
    expect(user.points.count).to eq(1)
  end

  it 'fails without advancing the checkpoint when speed units are unknown' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)
    stub_drives(car_id: 1, drive_id: 11, unit: 'parsecs')
    stub_drive(car_id: 1, drive_id: 11, unit: 'parsecs', detail: {
                 detail_id: 111, date: '2026-09-01T10:00:00Z',
                 latitude: 52.52, longitude: 13.405, speed: 36
               })

    expect { described_class.new(user).call }
      .to raise_error(TeslaMate::Sync::IncompleteError, /unsupported length unit: parsecs/)
    expect(user.reload.settings['teslamate_last_synced_at']).to be_nil
  end

  def stub_drives(car_id:, drive_id:, unit:)
    stub_request(:get, %r{#{base_url}/api/v1/cars/#{car_id}/drives})
      .to_return(status: 200, body: {
        data: { drives: [{ drive_id: drive_id }], units: { unit_of_length: unit } }
      }.to_json)
  end

  def stub_drive(car_id:, drive_id:, unit:, detail:)
    stub_request(:get, "#{base_url}/api/v1/cars/#{car_id}/drives/#{drive_id}")
      .to_return(status: 200, body: {
        data: { drive: { drive_id: drive_id, drive_details: [detail] },
                units: { unit_of_length: unit } }
      }.to_json)
  end
end
