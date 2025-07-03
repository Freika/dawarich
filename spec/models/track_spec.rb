require 'rails_helper'

RSpec.describe Track, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:start_at) }
    it { is_expected.to validate_presence_of(:end_at) }
    it { is_expected.to validate_presence_of(:original_path) }
    it { is_expected.to validate_numericality_of(:distance).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:avg_speed).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:duration).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:elevation_gain).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:elevation_loss).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:elevation_max).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:elevation_min).is_greater_than(0) }
  end
end
