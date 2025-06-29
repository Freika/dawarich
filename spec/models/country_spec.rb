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
end
