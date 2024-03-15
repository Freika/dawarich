require 'rails_helper'

RSpec.describe Point, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:import).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:latitude) }
    it { is_expected.to validate_presence_of(:longitude) }
    it { is_expected.to validate_presence_of(:tracker_id) }
    it { is_expected.to validate_presence_of(:timestamp) }
    it { is_expected.to validate_presence_of(:topic) }
  end
end
