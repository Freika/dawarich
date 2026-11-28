# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::ImportTripsJob do
  let(:user) { create(:user) }
  let(:source) { create(:trip_source, user:, importing: true, selection_token: 'token-1') }

  before do
    stub_host_addresses('trek.example.test', '93.184.216.34')
  end

  it 'reports the original failure when the source was disconnected mid-import' do
    boom = Class.new(StandardError)
    stub_const('Boom', boom)

    allow_any_instance_of(Trek::Sync).to receive(:fetch_trip) do
      TripSource.where(id: source.id).delete_all
      raise Boom, 'upstream blew up'
    end

    expect { described_class.new.perform(source.id, ['12'], 'token-1') }
      .to raise_error(Boom, 'upstream blew up')
  end
end
