# frozen_string_literal: true

require 'rails_helper'

RSpec.describe County, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:country) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:country) }
    it { is_expected.to belong_to(:state).optional }
  end
end
