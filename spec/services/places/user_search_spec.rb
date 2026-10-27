# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::UserSearch do
  let(:user) { create(:user) }
  let!(:place) { create(:place, user: user, latitude: 52, longitude: 13) }
  subject(:results) { described_class.new(user: user, latitude: 52, longitude: 13, radius: 0.1, limit: 50).call }

  it 'distinguishes saved Places with visits from unused Places for visit preselection' do
    unused = create(:place, user: user, latitude: 52.0001, longitude: 13)
    create(:visit, user: user, place: place)

    expect(results.find { |result| result[:id] == place.id }[:has_visits]).to be(true)
    expect(results.find { |result| result[:id] == unused.id }[:has_visits]).to be(false)
  end

  it 'includes a user Place with only suggested visits for visit preselection' do
    place.update!(source: :photon)
    create(:visit, user: user, place: place, status: :suggested)
    other_user = create(:user)
    other = create(:place, user: other_user, latitude: 52, longitude: 13)
    create(:visit, user: other_user, place: other)

    expect(results.map { |result| result[:id] }).to eq([place.id])
    expect(results.first[:has_visits]).to be(true)
  end
end
