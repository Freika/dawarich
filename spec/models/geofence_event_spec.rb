# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvent, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:source) }
    it { is_expected.to validate_presence_of(:occurred_at) }
    it { is_expected.to validate_presence_of(:received_at) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:area) }
    it { is_expected.to have_many(:webhook_deliveries).dependent(:destroy) }
  end

  describe 'enums' do
    it do
      expect(subject).to define_enum_for(:event_type)
        .with_values(enter: 0, leave: 1)
        .with_prefix(:event_type)
    end
    it do
      expect(subject).to define_enum_for(:source)
        .with_values(native_app: 0, server_inferred: 1, owntracks_native: 2)
        .with_prefix(:source)
    end
  end

  describe 'factory' do
    it 'is valid' do
      expect(build(:geofence_event)).to be_valid
    end
  end
end
