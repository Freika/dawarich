# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::ReverseCommands do
  before { Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } } }

  def key_exists?(id)
    Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(id)) } == 1
  end

  describe '.enqueue_points' do
    it "Sidekiq-owned enqueue_points enqueues today's per-point jobs" do
      ids = [101, 102, 103]

      expect do
        described_class.enqueue_points(9, ids, force: false, producer: 'spec')
      end.to have_enqueued_job(ReverseGeocodingJob).with('Point', 101, force: false)
                                                   .and have_enqueued_job(ReverseGeocodingJob)
        .with('Point', 102, force: false)
        .and have_enqueued_job(ReverseGeocodingJob)
        .with('Point', 103, force: false)

      ids.each do |id|
        ttl = Sidekiq.redis { |r| r.ttl(Point.geocode_dedup_key(id)) }
        expect(ttl).to be > 0
        expect(ttl).to be <= 86_400
      end
      expect(JobOutbox.count).to eq(0)
    end

    it 'Oban-owned enqueue_points writes one row per 100 ids' do
      job_owner!('command:geocoding.reverse_point', :oban)
      ids = (1..250).to_a

      expect do
        described_class.enqueue_points(9, ids, force: false, producer: 'spec')
      end.not_to have_enqueued_job(ReverseGeocodingJob)

      rows = JobOutbox.where(command_type: 'geocoding.reverse_point').order(:created_at)
      expect(rows.map { |r| r.payload['point_ids'] }).to eq([(1..100).to_a, (101..200).to_a, (201..250).to_a])
      expect(rows.map { |r| r.payload['user_id'] }.uniq).to eq([9])
      expect(rows.map { |r| r.payload['force'] }.uniq).to eq([false])
      expect(rows.map(&:aggregate_id).uniq).to eq([9])
    end

    it 'a claimed key is skipped; force clears keys' do
      ids = [201, 202, 203]
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(201), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      expect do
        described_class.enqueue_points(9, ids, force: false, producer: 'spec')
      end.to have_enqueued_job(ReverseGeocodingJob).exactly(2).times
                                                   .and have_enqueued_job(ReverseGeocodingJob)
        .with('Point', 202, force: false)
        .and have_enqueued_job(ReverseGeocodingJob)
        .with('Point', 203, force: false)

      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(201), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      expect do
        described_class.enqueue_points(9, ids, force: true, producer: 'spec')
      end.to have_enqueued_job(ReverseGeocodingJob).exactly(3).times

      ids.each { |id| expect(key_exists?(id)).to be false }
    end

    it 'a failing produce clears the claimed keys and raises' do
      foreign_id = 301
      ids = [302, 303]
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(foreign_id), 1, ex: Point::GEOCODE_DEDUP_TTL) }
      allow(JobCommands).to receive(:produce).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect do
        described_class.enqueue_points(9, ids, force: false, producer: 'spec')
      end.to raise_error(ActiveRecord::StatementInvalid)

      ids.each { |id| expect(key_exists?(id)).to be false }
      expect(key_exists?(foreign_id)).to be true
    end
  end

  context 'with phoenix.once_claims' do
    let(:user) { create(:user) }
    let(:keys) { ->(ids) { ids.map { Point.geocode_dedup_key(_1) } } }

    before { phoenix_state! }

    def claimed_keys = ActiveRecord::Base.connection.select_values('SELECT key FROM phoenix.once_claims ORDER BY key')

    it 'claims rows only for points without a live claim, and clears them on force' do
      PhoenixClaims.claim(Point.geocode_dedup_key(2), 60)
      expect(JobCommands).to receive(:produce)
        .with('geocoding.reverse_point', { 'user_id' => user.id, 'point_ids' => [1, 3], 'force' => false },
              aggregate_id: user.id, producer: 'spec')

      described_class.enqueue_points(user.id, [1, 2, 3], force: false, producer: 'spec')
      expect(claimed_keys).to match_array(keys.call([1, 2, 3]))

      allow(JobCommands).to receive(:produce)
      described_class.enqueue_points(user.id, [1, 2, 3], force: true, producer: 'spec')
      expect(claimed_keys).to be_empty
    end

    it 'releases the rows it claimed when producing fails' do
      allow(JobCommands).to receive(:produce).and_raise(RuntimeError, 'outbox down')

      expect { described_class.enqueue_points(user.id, [5], force: false, producer: 'spec') }
        .to raise_error(RuntimeError, 'outbox down')
      expect(claimed_keys).to be_empty
    end

    it 'uses the key Phoenix releases' do
      source = Rails.root.join('app-phoenix/lib/dawarich/geocoding/reverse_point_worker.ex').read
      expect(source).to include("\"geocode:enq:Point:\#{id}\"")
    end
  end
end
