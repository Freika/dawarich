# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:kind) }
  end

  describe 'action_path' do
    let(:user) { create(:user) }

    it 'accepts no path or a local path' do
      [nil, '/exports', '/imports/5?tab=x'].each do |path|
        expect(build(:notification, user:, action_path: path)).to be_valid
      end
    end

    it 'rejects anything that could leave the site' do
      ['https://evil.example', '//evil.example', '/\\evil.example', "/\t/evil.example", "/\n/evil.example",
       '/a b', 'javascript:alert(1)', 'exports'].each do |path|
        expect(build(:notification, user:, action_path: path)).not_to be_valid, "expected #{path.inspect} to be invalid"
      end
    end

    describe '#safe_action_path' do
      it 'returns a valid stored path' do
        expect(create(:notification, user:, action_path: '/exports').safe_action_path).to eq('/exports')
      end

      it 'returns nil for a path written without validation' do
        notification = create(:notification, user:)

        ['//evil.example', "/\t/evil.example"].each do |path|
          notification.update_column(:action_path, path)

          expect(notification.reload.safe_action_path).to be_nil
        end
      end

      it 'returns nil when there is no path' do
        expect(build(:notification).safe_action_path).to be_nil
      end
    end
  end

  describe 'live bell item' do
    include ActionCable::TestHelper
    include Turbo::Streams::StreamName

    it 'is rendered in the language of the person who receives it' do
      recipient = create(:user, settings: { 'locale' => 'de' })
      stream = stream_name_from([recipient, :notifications])

      # The commit, and with it the broadcast, happens after the recipient's
      # locale block ends, back in the locale of whoever acted (French here).
      I18n.with_locale(:fr) do
        ActiveRecord::Base.transaction do
          I18n.with_locale(:de) { create(:notification, user: recipient, title: 'Titel') }
        end
      end

      prepend = broadcasts(stream).map { |message| ActiveSupport::JSON.decode(message) }
                                  .find { |html| html.include?('action="prepend"') }
      expect(prepend).to include('Titel', 'vor ')
    end
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
