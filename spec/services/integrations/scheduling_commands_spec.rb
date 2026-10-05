# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Integrations::SchedulingCommands' do
  it 'AirTrail reverse handler enqueues the unchanged import leaf for its source user' do
    user = create(:user, status: :inactive)
    other = create(:user)
    handler = RailsCommands::Registry.handler('integrations.airtrail_flights')
    expect(handler).to be_present
    payload = { 'user_id' => user.id, 'event_id' => SecureRandom.uuid }

    expect { handler.call(payload) }
      .to have_enqueued_job(AirTrail::ImportFlightsJob).with(user.id).exactly(:once)
    expect(AirTrail::ImportFlightsJob).not_to have_been_enqueued.with(other.id)
    clear_enqueued_jobs
    expect { handler.call(payload) }
      .to have_enqueued_job(AirTrail::ImportFlightsJob).with(user.id).exactly(:once)
    clear_enqueued_jobs
    expect { handler.call(payload.merge('user_id' => -1)) }.not_to have_enqueued_job
  end
  it 'retained TeslaMate and Trek reverse handlers validate source user pairing and preserve leaf arguments' do
    stub_host_addresses('trek.example.test', '93.184.216.34')
    user = create(:user)
    other = create(:user)
    source = create(:trip_source, user: user)
    event_id = Integrations::SchedulingCommands.event_id('teslamate', 1_759_050_000, user.id)
    tesla = RailsCommands::Registry.handler('integrations.teslamate_sync')
    trek = RailsCommands::Registry.handler('integrations.trek_sync')
    expect(tesla).to be_present
    expect(trek).to be_present
    payload = { 'user_id' => user.id, 'event_id' => event_id }
    expect { 2.times { tesla.call(payload) } }
      .to have_enqueued_job(TeslaMate::SyncJob).with(user.id).exactly(:twice)
    expect { 2.times { trek.call(payload.merge('source_id' => source.id)) } }
      .to have_enqueued_job(Trek::SyncJob).with(source.id).exactly(:twice)
    clear_enqueued_jobs
    expect { trek.call(payload.merge('source_id' => source.id, 'user_id' => other.id)) }
      .not_to have_enqueued_job
    expect { trek.call(payload.merge('source_id' => -1)) }.not_to have_enqueued_job
    expect { tesla.call(payload.merge('user_id' => -1)) }.not_to have_enqueued_job
  end
end
