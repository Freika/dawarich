# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Create do
  describe '#call' do
    let(:user) { create(:user) }
    let(:attributes) { { user:, kind: :error, title: 'Failed', content: 'boom' } }

    it 'creates a notification each time by default' do
      2.times { described_class.new(**attributes).call }

      expect(user.notifications.count).to eq(2)
    end

    context 'with deduplicate' do
      it 'skips an identical unread notification' do
        2.times { described_class.new(**attributes, deduplicate: true).call }

        expect(user.notifications.count).to eq(1)
      end

      it 'creates the notification again once the earlier one is read' do
        described_class.new(**attributes, deduplicate: true).call
        user.notifications.update_all(read_at: Time.current)
        described_class.new(**attributes, deduplicate: true).call

        expect(user.notifications.count).to eq(2)
      end

      it 'creates notifications that differ in content, title or kind' do
        described_class.new(**attributes, deduplicate: true).call
        described_class.new(**attributes, content: 'other', deduplicate: true).call
        described_class.new(**attributes, title: 'Other', deduplicate: true).call
        described_class.new(**attributes, kind: :warning, deduplicate: true).call

        expect(user.notifications.count).to eq(4)
      end
    end
  end
end
