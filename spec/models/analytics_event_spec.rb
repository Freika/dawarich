# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalyticsEvent, type: :model do
  describe '.record' do
    let(:user) { create(:user) }

    it 'stores the event and returns it' do
      event = described_class.record(user:, event: :import_succeeded, dedup_key: 'import:1', properties: { files: 1 })

      expect(event).to be_persisted
      expect(event).to be_event_import_succeeded
      expect(event.properties).to eq('files' => 1)
    end

    it 'returns nil and stores nothing new when the dedup key was already recorded' do
      described_class.record(user:, event: :import_succeeded, dedup_key: 'import:1')

      expect(described_class.record(user:, event: :import_succeeded, dedup_key: 'import:1')).to be_nil
      expect(described_class.count).to eq(1)
    end
  end
end
