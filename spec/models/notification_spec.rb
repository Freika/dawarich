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
        read_notification # ensure it's created
        unread_notification # ensure it's created

        unread_notifications = described_class.unread
        expect(unread_notifications).to include(unread_notification)
        expect(unread_notifications).not_to include(read_notification)
      end
    end
  end
end
