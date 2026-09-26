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

    it 'keeps the import in flight and re-raises when the translator blows up' do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate).and_raise('boom')

      expect { described_class.new.perform(import.id) }.to raise_error(/boom/)

      expect(import.reload.additional_data_extraction_status).to eq('pending')
      expect(import.extraction_error_message).to eq('boom')
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

  describe 'track generation for the points the extraction leaves untracked' do
    let(:first_timestamp) { Time.zone.parse('2025-04-01T10:00:00Z').to_i }
    let(:generation_arguments) do
      [user.id, { start_at: Time.zone.at(first_timestamp), end_at: Time.zone.at(first_timestamp + 120),
                  mode: :bulk, untracked_only: true, import_id: import.id }]
    end

    before do
      3.times do |i|
        create(:point, user: user, import_id: import.id, timestamp: first_timestamp + (i * 60),
                       lonlat: "POINT(#{12.3712 + (i * 0.001)} 51.3402)")
      end
    end

    def attach_file(body)
      import.file.attach(io: StringIO.new(body), filename: 'Timeline.json', content_type: 'application/json')
    end

    it 'schedules generation once the extraction completes' do
      attach_file(File.read(Rails.root.join('spec/fixtures/files/enhanced_import/google_phone_takeout_minimal.json')))

      described_class.perform_now(import.id)

      expect(import.reload.additional_data_extraction_status).to eq('completed')
      expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(*generation_arguments)
    end

    it 'retries a failed extraction without scheduling generation' do
      attach_file('{"semanticSegments": [{"startTime": ')

      described_class.perform_now(import.id)

      expect(described_class).to have_been_enqueued.with(import.id)
      expect(Tracks::ParallelGeneratorJob).not_to have_been_enqueued
    end

    it 'keeps holding the points between attempts' do
      attach_file('{"semanticSegments": [{"startTime": ')

      described_class.perform_now(import.id)

      expect(import.reload.additional_data_extraction_status).to eq('pending')
      expect(Import.awaiting_extraction).to include(import)
      expect(Imports::ExtractionPolicy.new(user, import).create?).to be(false)
    end

    it 'schedules generation once the third failed attempt exhausts the retries' do
      attach_file('{"semanticSegments": [{"startTime": ')
      job = described_class.new(import.id)
      job.exception_executions = { '[StandardError]' => 2 }

      job.perform_now

      expect(described_class).not_to have_been_enqueued
      expect(import.reload.additional_data_extraction_status).to eq('failed')
      expect(import.extraction_error_message).to be_present
      expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(*generation_arguments)
    end

    it 'schedules generation when deadlock retries are exhausted' do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate)
        .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
      job = described_class.new(import.id)
      job.exception_executions = { '[ActiveRecord::Deadlocked]' => 2 }

      job.perform_now

      expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(*generation_arguments)
    end

    it 'does not schedule generation while it waits for the user lock' do
      allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(Tracks::PerUserLock::AcquisitionTimeout)

      described_class.perform_now(import.id)

      expect(described_class).to have_been_enqueued.with(import.id, attempt: 2)
      expect(Tracks::ParallelGeneratorJob).not_to have_been_enqueued
    end

    it 'schedules generation once it gives up on the user lock' do
      allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(Tracks::PerUserLock::AcquisitionTimeout)

      described_class.perform_now(import.id, attempt: described_class::MAX_LOCK_ATTEMPTS)

      expect(import.reload.additional_data_extraction_status).to eq('failed')
      expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(*generation_arguments)
    end

    describe 'reporting the final failure' do
      def exhausted_job
        described_class.new(import.id).tap { |job| job.exception_executions = { '[StandardError]' => 2 } }
      end

      def fail_first_import_lookup(then_return: :original)
        lookups = 0
        allow(Import).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
          lookups += 1
          raise ActiveRecord::ConnectionNotEstablished, 'connection lost' if lookups == 1

          then_return == :original ? original.call(*args, **kwargs) : then_return
        end
      end

      before { allow(ExceptionReporter).to receive(:call) }

      it 'does not report a failed attempt that will be retried' do
        attach_file('{"semanticSegments": [{"startTime": ')

        described_class.perform_now(import.id)

        expect(ExceptionReporter).not_to have_received(:call)
      end

      it 'reports the error of the attempt that exhausts the retries once' do
        attach_file('{"semanticSegments": [{"startTime": ')

        exhausted_job.perform_now

        expect(ExceptionReporter).to have_received(:call).once.with(instance_of(Oj::ParseError))
      end

      it 'reports an error raised before the extraction starts once the retries are exhausted' do
        fail_first_import_lookup

        exhausted_job.perform_now

        expect(ExceptionReporter).to have_received(:call).once.with(instance_of(ActiveRecord::ConnectionNotEstablished))
        expect(import.reload.additional_data_extraction_status).to eq('failed')
        expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(*generation_arguments)
      end

      it 'stays silent when the import is gone by the time the retries are exhausted' do
        fail_first_import_lookup(then_return: nil)

        exhausted_job.perform_now

        expect(ExceptionReporter).not_to have_received(:call)
        expect(Tracks::ParallelGeneratorJob).not_to have_been_enqueued
      end

      it 'reports exhausted deadlock retries once' do
        allow_any_instance_of(EnhancedImport::Translator).to receive(:translate)
          .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
        job = described_class.new(import.id)
        job.exception_executions = { '[ActiveRecord::Deadlocked]' => 2 }

        job.perform_now

        expect(ExceptionReporter).to have_received(:call).once.with(instance_of(ActiveRecord::Deadlocked))
      end
    end

    describe 'a record that disappears during the extraction' do
      before do
        allow_any_instance_of(EnhancedImport::Translator).to receive(:translate)
          .and_raise(ActiveRecord::RecordNotFound, 'gone')
        allow(ExceptionReporter).to receive(:call)
      end

      it 'is retried like any other failure' do
        described_class.perform_now(import.id)

        expect(described_class).to have_been_enqueued.with(import.id)
        expect(Tracks::ParallelGeneratorJob).not_to have_been_enqueued
      end

      it 'schedules generation and reports once when the retries are exhausted' do
        job = described_class.new(import.id)
        job.exception_executions = { '[StandardError]' => 2 }

        job.perform_now

        expect(import.reload.additional_data_extraction_status).to eq('failed')
        expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(*generation_arguments)
        expect(ExceptionReporter).to have_received(:call).once.with(instance_of(ActiveRecord::RecordNotFound))
      end
    end
  end
end
