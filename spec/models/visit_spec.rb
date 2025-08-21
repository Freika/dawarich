# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visit, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:area).optional }
    it { is_expected.to belong_to(:place).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }
    it { is_expected.to validate_presence_of(:duration) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates ended_at is greater than started_at' do
      visit = build(:visit, started_at: Time.zone.now, ended_at: Time.zone.now - 1.hour)

      expect(visit).not_to be_valid
      expect(visit.errors[:ended_at]).to include("must be greater than #{visit.started_at}")
    end
  end

  describe 'factory' do
    it { expect(build(:visit)).to be_valid }
  end
end
