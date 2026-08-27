# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Country, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:iso_a2) }
    it { is_expected.to validate_presence_of(:iso_a3) }
    it { is_expected.to validate_presence_of(:geom) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe '.matching_name' do
    it 'resolves duplicate names to the lowest id, matching the backfill' do
      first = create(:country, name: 'Duplicastan')
      create(:country, name: 'Duplicastan', iso_a2: 'DP', iso_a3: 'DPX')

      expect(described_class.matching_name('Duplicastan')).to eq(first)
    end
  end
end
