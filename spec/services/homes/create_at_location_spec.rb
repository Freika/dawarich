# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Homes::CreateAtLocation do
  subject(:home) { described_class.new(user:, latitude: 52.52, longitude: 13.405).call }

  let(:user) { create(:user) }

  it 'creates a place and an open-dated Home there' do
    expect(home).to have_attributes(user:, started_on: nil, ended_on: nil)
    expect(home.place).to have_attributes(user:, source: 'manual', name: I18n.t('trip_detection.home_place_name'))
    expect(home.place.lat).to be_within(0.0001).of(52.52)
  end

  it 'reuses a place the user already has at that spot' do
    existing = create(:place, user:, latitude: 52.52, longitude: 13.405)
    expect(home.place).to eq(existing)
  end

  it 'adopts a reused demo place' do
    existing = create(:place, user:, latitude: 52.52, longitude: 13.405, demo: true)
    expect(home.place).to eq(existing)
    expect(existing.reload).not_to be_demo
  end

  it 'does not reuse an archived place' do
    create(:place, user:, latitude: 52.52, longitude: 13.405, archived: true)
    expect { home }.to change(user.places, :count).by(1)
  end

  it 'returns the same Home when called twice' do
    expect(described_class.new(user:, latitude: 52.52, longitude: 13.405).call).to eq(home)
    expect(user.homes.count).to eq(1)
  end

  it 'enqueues Trip Detection' do
    expect { home }.to have_enqueued_job(Trips::DetectJob).with(user.id)
  end
end
