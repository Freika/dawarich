# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::ImportFromJsonJob, type: :job do
  let(:user) { create(:user) }
  let(:json_string) { file_fixture('air_trail/export_v3.json').read }

  it 'imports flights and notifies the user' do
    described_class.perform_now(user.id, json_string)

    expect(user.flights.count).to eq(1)
    notification = user.notifications.last
    expect(notification.kind).to eq('info')
    expect(notification.content).to include('1 created')
  end

  it 'notifies the user and re-raises on parser errors' do
    expect { described_class.perform_now(user.id, 'not json') }
      .to raise_error(Flights::Parsers::Error)

    notification = user.notifications.last
    expect(notification.kind).to eq('error')
    expect(notification.content).to include('Invalid JSON')
  end

  it 'no-ops for a missing user' do
    expect { described_class.perform_now(-1, json_string) }.not_to raise_error
  end
end
