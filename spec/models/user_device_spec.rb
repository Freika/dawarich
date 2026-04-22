# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserDevice, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:platform) }
    it { is_expected.to validate_presence_of(:device_id) }

    describe 'uniqueness of device_id scoped to user' do
      subject { create(:user_device) }
      it { is_expected.to validate_uniqueness_of(:device_id).scoped_to(:user_id) }
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'enums' do
    it do
      expect(subject).to define_enum_for(:platform)
        .with_values(ios: 0, android: 1)
        .with_prefix(:platform)
    end
  end
end
