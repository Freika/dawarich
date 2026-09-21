# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LegacyAreaPlaceMapping, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:area) }
    it { is_expected.to belong_to(:place) }
  end

  it 'maps an area to a place owned by the same user' do
    user = create(:user)
    mapping = described_class.new(area: create(:area, user: user), place: create(:place, user: user))

    expect(mapping).to be_valid
  end

  it 'rejects a place owned by another user' do
    mapping = described_class.new(area: create(:area), place: create(:place))

    expect(mapping).not_to be_valid
    expect(mapping.errors[:place]).to include('must belong to the same user as the area')
  end

  it 'maps an area only once' do
    user = create(:user)
    area = create(:area, user: user)
    described_class.create!(area: area, place: create(:place, user: user))

    duplicate = described_class.new(area: area, place: create(:place, user: user))

    expect(duplicate).not_to be_valid
  end
end
