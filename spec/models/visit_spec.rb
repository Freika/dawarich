# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visit, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:area).optional }
    it { is_expected.to belong_to(:place).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'factory' do
    it { expect(build(:visit)).to be_valid }
  end
end
