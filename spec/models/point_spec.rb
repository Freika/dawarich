# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Point, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:import).optional }
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:latitude) }
    it { is_expected.to validate_presence_of(:longitude) }
    it { is_expected.to validate_presence_of(:timestamp) }
    # Disabled them (for now) because they are not present in the Overland data
    xit { is_expected.to validate_presence_of(:tracker_id) }
    xit { is_expected.to validate_presence_of(:topic) }
  end
end
