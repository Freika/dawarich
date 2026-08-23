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

    it 'stamps every point with its source dimension' do
      described_class.perform_now

      expect(Point.where(source_id: nil).count).to eq(0)
    end

    it 'points with identical combos share one source row' do
      described_class.perform_now

      expect(phone_points.map { |p| p.reload.source_id }.uniq.size).to eq(1)
      expect(watch_point.reload.source_id).not_to eq(phone_points.first.reload.source_id)
    end

    it 'is idempotent on re-run' do
      described_class.perform_now
      stamped = Point.order(:id).pluck(:source_id)

      expect { described_class.perform_now }.not_to change(PointSource, :count)
      expect(Point.order(:id).pluck(:source_id)).to eq(stamped)
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

    it 'hands off to the country backfill only once it has finished' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      expect { described_class.perform_now(Point.minimum(:id)) }.not_to \
        have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)

      expect { described_class.perform_now(Point.maximum(:id)) }.to \
        have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
    end

    it 'covers every point across a chained run over a gapped id range' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      hole = create(:point, user: user, tracker_id: 'gap-filler')
      tail = create(:point, user: user, tracker_id: 'tail')
      hole.delete

      perform_enqueued_jobs(only: described_class) { described_class.perform_now }

      expect(Point.where(source_id: nil)).to be_empty
      expect(tail.reload.source_id).to be_present
    end

    # A statement_timeout usually means the batch is too big, not unlucky;
    # retrying it identically ten times churns rolled-back work for an hour.
    it 'halves the batch and retries the same cursor when a batch is aborted' do
      connection = ActiveRecord::Base.connection
      allow(connection).to receive(:execute).and_call_original
      allow(connection).to receive(:execute)
        .with(/INSERT INTO point_sources/).and_raise(ActiveRecord::QueryCanceled)
      start_id = Point.minimum(:id)

      expect { described_class.perform_now(start_id) }.to \
        have_enqueued_job(described_class).with(start_id, described_class::BATCH_SIZE / 2)
    end

    it 'hands the smallest batch to the retry machinery instead of shrinking forever' do
      connection = ActiveRecord::Base.connection
      allow(connection).to receive(:execute).and_call_original
      allow(connection).to receive(:execute)
        .with(/INSERT INTO point_sources/).and_raise(ActiveRecord::QueryCanceled)
      start_id = Point.minimum(:id)

      # retry_on re-enqueues with the arguments unchanged — same cursor, same
      # floor size — rather than the rescue enqueueing a smaller batch.
      expect { described_class.perform_now(start_id, described_class::MIN_BATCH_SIZE) }.to \
        have_enqueued_job(described_class).with(start_id, described_class::MIN_BATCH_SIZE)
    end

    it 'tells the operator to resume a halved batch at its halved size' do
      allow(Rails.logger).to receive(:error)
      job = described_class.new(42, described_class::MIN_BATCH_SIZE)

      described_class.log_exhaustion(job, ActiveRecord::QueryCanceled.new('canceled'))

      expect(Rails.logger).to have_received(:error)
        .with(/perform_later\(42, #{described_class::MIN_BATCH_SIZE}\)/)
    end

    it 'reports batch position so operators can tell running from stalled' do
      allow(Rails.logger).to receive(:info).and_call_original

      described_class.perform_now

      expect(Rails.logger).to have_received(:info).with(/of id range/)
    end

    it 'keeps walking when points are appended while the chain runs' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      last_id = Point.maximum(:id)

      # The same cursor ends the chain before the append and continues it
      # after, so only the newly appended point can account for the difference.
      expect { described_class.perform_now(last_id) }.not_to have_enqueued_job(described_class)

      create(:point, user: user, tracker_id: 'appended')

      expect { described_class.perform_now(last_id) }.to \
        have_enqueued_job(described_class).with(last_id + 1)
    end
  end
end
