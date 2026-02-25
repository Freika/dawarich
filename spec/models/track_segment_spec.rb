# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegment, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:track) }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:transportation_mode)
        .with_values(
          unknown: 0,
          stationary: 1,
          walking: 2,
          running: 3,
          cycling: 4,
          driving: 5,
          bus: 6,
          train: 7,
          flying: 8,
          boat: 9,
          motorcycle: 10
        )
    end

    it do
      is_expected.to define_enum_for(:confidence)
        .with_values(low: 0, medium: 1, high: 2)
        .with_prefix(true)
    end
  end

  describe 'validations' do
    subject { build(:track_segment) }

    it { is_expected.to validate_presence_of(:transportation_mode) }
    it { is_expected.to validate_presence_of(:start_index) }
    it { is_expected.to validate_presence_of(:end_index) }

    it { is_expected.to validate_numericality_of(:start_index).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:end_index).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:distance).only_integer.is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:duration).only_integer.is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:avg_speed).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_speed).is_greater_than_or_equal_to(0).allow_nil }

    context 'when end_index is less than start_index' do
      let(:segment) { build(:track_segment, start_index: 10, end_index: 5) }

      it 'is invalid' do
        expect(segment).not_to be_valid
        expect(segment.errors[:end_index]).to include('must be greater than or equal to start_index')
      end
    end

    context 'when end_index equals start_index' do
      let(:segment) { build(:track_segment, start_index: 5, end_index: 5) }

      it 'is valid' do
        expect(segment).to be_valid
      end
    end
  end

  describe 'factory' do
    it 'has a valid default factory' do
      expect(build(:track_segment)).to be_valid
    end

    it 'has valid trait factories' do
      %i[walking cycling running train flying stationary from_source].each do |trait|
        expect(build(:track_segment, trait)).to be_valid
      end
    end
  end
end
