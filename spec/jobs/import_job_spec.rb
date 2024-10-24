# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(user.id, import.id) }

    let(:user) { create(:user) }
    let!(:import) { create(:import, user:, name: 'owntracks_export.json') }
    let!(:import_points) { create_list(:point, 9, import: import) }
    let(:start_at) { Time.zone.at(1_709_283_789) } # Timestamp of the first point in the "2024-03.rec" fixture file
    let(:end_at) { import.points.reload.order(:timestamp).last.recorded_at }

    it 'creates points' do
      expect { perform }.to change { Point.count }.by(9)
    end

    it 'calls Stats::CalculatingJob' do
      expect(Stats::CalculatingJob).to receive(:perform_later).with(user.id, start_at:, end_at:)

      perform
    end

    it 'creates a notification' do
      expect { perform }.to change { Notification.count }.by(1)
    end

    context 'when there is an error' do
      before do
        allow_any_instance_of(OwnTracks::ExportParser).to receive(:call).and_raise(StandardError)
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
