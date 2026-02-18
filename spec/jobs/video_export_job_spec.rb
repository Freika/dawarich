# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExportJob do
  let(:video_export) { create(:video_export, status: :created) }

  describe '#perform' do
    it 'updates status to processing and calls RequestRender' do
      allow(VideoExports::RequestRender).to receive_message_chain(:new, :call)

      described_class.perform_now(video_export.id)

      expect(video_export.reload).to be_processing
    end

    context 'when an error occurs' do
      before do
        allow(VideoExports::RequestRender).to receive(:new).and_raise(StandardError, 'Connection refused')
      end

      it 'marks the export as failed with error message' do
        described_class.perform_now(video_export.id)

        video_export.reload
        expect(video_export).to be_failed
        expect(video_export.error_message).to eq('Connection refused')
      end
    end
  end
end
