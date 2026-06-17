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
end
