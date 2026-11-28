# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Area, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:visits).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:latitude) }
    it { is_expected.to validate_presence_of(:longitude) }
    it { is_expected.to validate_presence_of(:radius) }
    it { is_expected.to validate_numericality_of(:radius).is_greater_than(0) }

    it do
      is_expected.to validate_numericality_of(:latitude)
        .is_greater_than_or_equal_to(-90).is_less_than_or_equal_to(90)
    end

    it do
      is_expected.to validate_numericality_of(:longitude)
        .is_greater_than_or_equal_to(-180).is_less_than_or_equal_to(180)
    end
  end

  describe '#visit_radius' do
    it 'caps a legacy radius at the maximum Visit Radius' do
      expect(build(:area, radius: Place::MAX_VISIT_RADIUS * 2).visit_radius).to eq(Place::MAX_VISIT_RADIUS)
    end

    it 'falls back to the default Visit Radius for a non-positive radius' do
      expect(build(:area, radius: 0).visit_radius).to eq(Place.column_defaults['visit_radius'])
    end
  end

  describe 'factory' do
    it { expect(build(:area)).to be_valid }
  end
end
