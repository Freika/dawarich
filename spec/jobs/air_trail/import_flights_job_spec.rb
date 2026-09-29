# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::ImportFlightsJob, type: :job do
  it 'calls ImportFlights for the user' do
    user = create(:user)
    service = instance_double(AirTrail::ImportFlights, call: { created: 0 })
    allow(AirTrail::ImportFlights).to receive(:new).with(user).and_return(service)

    described_class.perform_now(user.id)

    expect(service).to have_received(:call)
  end

  it 'no-ops for a missing user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'notifies the user and re-raises when the sync fails' do
    user = create(:user)
    service = instance_double(AirTrail::ImportFlights)
    allow(service).to receive(:call).and_raise(AirTrail::Client::Error, 'connection refused')
    allow(AirTrail::ImportFlights).to receive(:new).with(user).and_return(service)

    expect { described_class.perform_now(user.id) }.to raise_error(AirTrail::Client::Error)

    notification = user.notifications.last
    expect(notification.kind).to eq('error')
    expect(notification.content).to include('connection refused')
  end

  it 'notifies a failed sync in the user saved locale' do
    user = create(:user, settings: { 'locale' => 'fr' })
    service = instance_double(AirTrail::ImportFlights)
    allow(service).to receive(:call).and_raise(AirTrail::Client::Error, 'connexion refusée')
    allow(AirTrail::ImportFlights).to receive(:new).with(user).and_return(service)

    expect { I18n.with_locale(:en) { described_class.perform_now(user.id) } }
      .to raise_error(AirTrail::Client::Error)

    expect(user.notifications.last.title).to eq('La synchronisation AirTrail a échoué')
  end

  it 'forwards without calling AirTrail while Oban owns the command' do
    user = create(:user)
    job_owner!(ImportCommands::AIRTRAIL_FLIGHTS_KEY, :oban)
    expect(AirTrail::ImportFlights).not_to receive(:new)
    job = described_class.new(user.id)

    job.perform_now

    expect(JobOutbox.pending.sole).to have_attributes(event_id: job.job_id, command_type: 'imports.airtrail_flights',
                                                      payload: { 'user_id' => user.id })
  end

  it 'forwards when the owner moves between the pre-check and the gate' do
    user = create(:user)
    service = instance_double(AirTrail::ImportFlights, call: :not_owner)
    allow(AirTrail::ImportFlights).to receive(:new).with(user).and_return(service)
    job = described_class.new(user.id)

    job.perform_now

    expect(JobOutbox.pending.sole).to have_attributes(event_id: job.job_id, payload: { 'user_id' => user.id })
  end
end
