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
end
