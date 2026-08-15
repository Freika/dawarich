# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::ExtractJob do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }

  describe 'state transitions' do
    it 'marks the import as completed with zero counts when no items are emitted' do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) { |&_block| }

      described_class.new.perform(import.id)

      expect(import.reload.additional_data_extraction_status).to eq('completed')
      expect(import.extraction_counts).to eq({})
      expect(import.additional_data_extraction['started_at']).to be_present
      expect(import.additional_data_extraction['completed_at']).to be_present
    end

    it 'marks the import as failed and re-raises when the translator blows up' do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate).and_raise('boom')

      expect { described_class.new.perform(import.id) }.to raise_error(/boom/)

      expect(import.reload.additional_data_extraction_status).to eq('failed')
      expect(import.extraction_error_message).to eq('boom')
    end

    it 'returns silently for an unsupported source' do
      gpx_import = create(:import, user: user, source: :gpx)
      expect { described_class.new.perform(gpx_import.id) }.not_to raise_error
      expect(gpx_import.reload.additional_data_extraction_status).not_to eq('running')
    end

    it 'returns silently when the import has been deleted' do
      expect { described_class.new.perform(0) }.not_to raise_error
    end
  end
end
