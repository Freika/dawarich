# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Swarm::Importer do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :swarm) }
  let(:file_path) { file_fixture('swarm/checkins1.json').to_s }

  before { described_class.new(import, user.id, file_path).call }

  it 'creates one point per check-in with real coordinates' do
    expect(user.points.count).to eq(4)
  end

  it 'reads coordinates from the check-in, not the venue' do
    point = user.points.find_by(timestamp: Time.utc(2024, 5, 4, 10, 45).to_i)

    expect(point.lat).to be_within(0.00001).of(51.33918)
    expect(point.lon).to be_within(0.00001).of(12.37266)
  end

  it 'treats createdAt as UTC regardless of the app time zone' do
    expect(user.points.order(:timestamp).first.timestamp).to eq(Time.utc(2024, 5, 4, 10).to_i)
  end

  it 'keeps venueless check-ins as points' do
    expect(user.points.where(timestamp: Time.utc(2024, 5, 4, 15).to_i).count).to eq(2)
  end
end
