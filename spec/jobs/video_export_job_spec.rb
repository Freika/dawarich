# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExportJob do
  let(:video_export) { create(:video_export, status: :created) }

  describe '#perform' do
    it 'updates status to processing and calls RequestRender' do
      render_service = instance_double(VideoExports::RequestRender, call: nil)
      allow(VideoExports::RequestRender).to receive(:new).and_return(render_service)

      described_class.perform_now(video_export.id)

      expect(video_export.reload).to be_processing
    end

    context 'when an error occurs during rendering' do
      let(:render_service) { instance_double(VideoExports::RequestRender) }

      before do
        allow(VideoExports::RequestRender).to receive(:new).and_return(render_service)
        allow(render_service).to receive(:call).and_raise(StandardError, 'Connection refused')
        allow(ExceptionReporter).to receive(:call)
      end

      it 'marks the export as failed with error message' do
        described_class.perform_now(video_export.id)

        video_export.reload
        expect(video_export).to be_failed
        expect(video_export.error_message).to eq('Connection refused')
      end

      it 'reports the exception' do
        described_class.perform_now(video_export.id)

        expect(ExceptionReporter).to have_received(:call).with(instance_of(StandardError))
      end

      it 'truncates long error messages to 500 characters' do
        allow(render_service).to receive(:call).and_raise(StandardError, 'x' * 1000)

        described_class.perform_now(video_export.id)

        expect(video_export.reload.error_message.length).to be <= 500
      end
    end

    context 'when the record has been deleted' do
      it 'returns early without raising or reporting' do
        deleted_id = video_export.id
        video_export.destroy!

        expect(ExceptionReporter).not_to receive(:call)

        expect { described_class.perform_now(deleted_id) }.not_to raise_error
      end
    end
  end
end
