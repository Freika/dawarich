# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::ProcessJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(import.id) }

    let(:user) { create(:user) }
    let!(:import) { create(:import, user:, name: '2024-03.rec') }
    let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }

    before do
      import.file.attach(io: File.open(file_path), filename: '2024-03.rec', content_type: 'application/octet-stream')
    end

    it 'creates points' do
      expect { perform }.to change { Point.count }.by(9)
    end

    it 'calls Stats::CalculatingJob' do
      # Timestamp of the first point in the "2024-03.rec" fixture file
      expect(Stats::CalculatingJob).to receive(:perform_later).with(user.id, 2024, 3)

      perform
    end

    context 'when there is an error' do
      before do
        allow_any_instance_of(OwnTracks::Importer).to receive(:call).and_raise(StandardError)
      end

      it 'does not create points' do
        expect { perform }.not_to(change { Point.count })
      end

      it 'creates a notification' do
        expect { perform }.to change { Notification.count }.by(1)
      end
    end
  end
end
