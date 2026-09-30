# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::ExtractJob do
  include ActiveJob::TestHelper

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
      allow(ExceptionReporter).to receive(:call)

      expect { described_class.new.perform(import.id) }.to raise_error(/boom/)

      expect(import.reload.additional_data_extraction_status).to eq('failed')
      expect(import.extraction_error_message).to eq('boom')
      expect(ExceptionReporter).to have_received(:call).with(instance_of(RuntimeError))
    end

    it 'marks malformed JSON as failed without reporting or retrying' do
      import.file.attach(
        io: StringIO.new('{"semanticSegments": ['),
        filename: 'Timeline.json',
        content_type: 'application/json'
      )
      allow(ExceptionReporter).to receive(:call)

      expect { described_class.new.perform(import.id) }.not_to raise_error

      expect(import.reload.additional_data_extraction_status).to eq('failed')
      expect(import.extraction_error_message).to match(/parse|terminated|closed|format/i)
      expect(ExceptionReporter).not_to have_received(:call)
    end

    it 'retries transient deadlocks without failing the import or reporting the first attempt' do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate)
        .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
      allow(ExceptionReporter).to receive(:call)

      expect do
        described_class.perform_now(import.id)
      end.to have_enqueued_job(described_class).with(import.id)

      expect(import.reload.additional_data_extraction_status).to eq('running')
      expect(ExceptionReporter).not_to have_received(:call)
    end

    it 'marks the import failed and reports after deadlock retries are exhausted' do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate)
        .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
      allow(ExceptionReporter).to receive(:call)

      job = described_class.new(import.id)
      job.exception_executions = { '[ActiveRecord::Deadlocked]' => 2 }

      expect { job.perform_now }.not_to have_enqueued_job(described_class)

      expect(import.reload.additional_data_extraction_status).to eq('failed')
      expect(import.extraction_error_message).to eq('deadlock detected')
      expect(ExceptionReporter).to have_received(:call).with(instance_of(ActiveRecord::Deadlocked))
    end

    it 'returns silently for an unsupported source' do
      kml_import = create(:import, user: user, source: :kml)
      expect { described_class.new.perform(kml_import.id) }.not_to raise_error
      expect(kml_import.reload.additional_data_extraction_status).not_to eq('running')
    end

    it 'returns silently when the import has been deleted' do
      expect { described_class.new.perform(0) }.not_to raise_error
    end
  end
end
