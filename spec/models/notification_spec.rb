# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:kind) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:kind).with_values(info: 0, warning: 1, error: 2) }
  end

  describe 'scopes' do
    describe '.unread' do
      let(:read_notification) { create(:notification, read_at: Time.current) }
      let(:unread_notification) { create(:notification, read_at: nil) }

      it 'returns only unread notifications' do
        expect(described_class.unread).to eq([unread_notification])
      end
    end
  end
end
