# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Track, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end
end
