# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Area, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:visits).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:latitude) }
    it { is_expected.to validate_presence_of(:longitude) }
    it { is_expected.to validate_presence_of(:radius) }
  end

  describe 'factory' do
    it { expect(build(:area)).to be_valid }
  end
end
