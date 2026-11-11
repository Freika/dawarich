# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Create do
  describe '#call' do
    let(:user) { create(:user) }
    let(:attributes) { { user:, kind: :error, title: 'Failed', content: 'boom' } }

    it 'skips a notification identical to one that is still unread' do
      2.times { described_class.new(**attributes).call }

      expect(user.notifications.count).to eq(1)
    end

    it 'skips an identical unread warning as well' do
      2.times { described_class.new(**attributes, kind: :warning).call }

      expect(user.notifications.count).to eq(1)
    end

    it 'creates an info notification every time, because each one is a separate event' do
      2.times { described_class.new(**attributes, kind: :info, title: 'Export finished').call }

      expect(user.notifications.count).to eq(2)
    end

    it 'creates the notification again once the earlier one is read' do
      described_class.new(**attributes).call
      user.notifications.update_all(read_at: Time.current)
      described_class.new(**attributes).call

      expect(user.notifications.count).to eq(2)
    end

    it 'creates notifications that differ in content, title or kind' do
      described_class.new(**attributes).call
      described_class.new(**attributes, content: 'other').call
      described_class.new(**attributes, title: 'Other').call
      described_class.new(**attributes, kind: :warning).call

      expect(user.notifications.count).to eq(4)
    end

    it "does not treat another user's notification as a duplicate" do
      described_class.new(**attributes).call
      described_class.new(**attributes, user: create(:user)).call

      expect(Notification.count).to eq(2)
    end

    it 'uses the title as the text when the caller has none, instead of raising' do
      2.times { described_class.new(**attributes, content: '').call }

      expect(user.notifications.pluck(:content)).to eq(['Failed'])
    end

    context 'with an action_path' do
      it 'stores where the notification leads' do
        described_class.new(**attributes, action_path: '/exports').call

        expect(user.notifications.last.action_path).to eq('/exports')
      end

      it 'skips an identical notification that leads to the same place' do
        2.times { described_class.new(**attributes, action_path: '/exports').call }

        expect(user.notifications.count).to eq(1)
      end

      it 'keeps notifications that lead to different places' do
        described_class.new(**attributes, action_path: '/exports').call
        described_class.new(**attributes, action_path: '/imports').call

        expect(user.notifications.count).to eq(2)
      end
    end

    it 'exposes route helpers for call sites' do
      expect(Notifications.paths.exports_path).to eq('/exports')
    end

    context 'with operator_only' do
      it 'notifies the user on a self-hosted instance' do
        described_class.new(**attributes, operator_only: true).call

        expect(user.notifications.count).to eq(1)
      end

      it 'stays silent on Cloud, where the user cannot act on it' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

        described_class.new(**attributes, operator_only: true).call

        expect(user.notifications.count).to eq(0)
      end
    end
  end
end
