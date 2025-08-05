# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Device, type: :model do
  describe 'validations' do
    subject { build(:device) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:identifier) }
    it { is_expected.to validate_uniqueness_of(:identifier).scoped_to(:user_id) }
  end
end
