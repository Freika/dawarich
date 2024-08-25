# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaceVisit, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:place) }
    it { is_expected.to belong_to(:visit) }
  end
end
