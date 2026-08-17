# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPointDimensionsJob, type: :job do
  let(:user) { create(:user) }

  let!(:phone_points) do
    create_list(:point, 2, user: user,
                           tracker_id: 'pixel-8', topic: 'owntracks/eugene/pixel',
                           motion_data: { 'activity' => 'walking' })
  end
  let!(:watch_point) do
    create(:point, user: user,
                   tracker_id: 'watch-ultra', topic: nil,
                   motion_data: {})
  end

  describe '#perform' do
    it 'creates one source row per distinct combo' do
      expect { described_class.perform_now }.to change(PointSource, :count).by(2)
    end

    it 'stamps every point with its source and motion dimension' do
      described_class.perform_now

      expect(Point.where(source_id: nil).count).to eq(0)
      expect(Point.where(motion_id: nil).count).to eq(0)
    end

    it 'points with identical combos share one source row' do
      described_class.perform_now

      expect(phone_points.map { |p| p.reload.source_id }.uniq.size).to eq(1)
      expect(watch_point.reload.source_id).not_to eq(phone_points.first.reload.source_id)
    end

    it 'deduplicates motion payloads through the digest' do
      described_class.perform_now

      expect(PointMotion.count).to eq(2)
      expect(phone_points.map { |p| p.reload.motion_id }.uniq.size).to eq(1)
    end

    it 'is idempotent on re-run' do
      described_class.perform_now
      stamped = Point.order(:id).pluck(:source_id, :motion_id)

      expect { described_class.perform_now }.not_to change(PointSource, :count)
      expect(Point.order(:id).pluck(:source_id, :motion_id)).to eq(stamped)
    end

    it 'walks the id range in batches by re-enqueueing itself' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      first_id = Point.minimum(:id)

      expect { described_class.perform_now(first_id) }.to \
        have_enqueued_job(described_class).with(first_id + 1)
    end

    it 'does not re-enqueue past the last point' do
      described_class.perform_now(Point.maximum(:id))

      expect(described_class).not_to have_been_enqueued
    end
  end
end
