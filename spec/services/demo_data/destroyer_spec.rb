# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DemoData::Destroyer do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when the user has demo data' do
      before { DemoData::Importer.new(user).call }

      it 'destroys demo visits, trips, and the import' do
        described_class.new(user).call
        expect(user.visits.demo.count).to eq(0)
        expect(user.trips.demo.count).to eq(0)
        expect(user.imports.where(demo: true).count).to eq(0)
      end

      it 'destroys demo points via import cascade' do
        described_class.new(user).call
        expect(user.points.count).to eq(0)
      end

      it 'destroys orphan demo tags' do
        described_class.new(user).call
        expect(user.tags.demo.count).to eq(0)
      end

      it 'preserves a demo place referenced by a non-demo visit' do
        place = Place.demo.where(user_id: user.id).first
        non_demo_visit = user.visits.create!(
          name: 'Real visit',
          place: place,
          started_at: 1.day.from_now,
          ended_at: 1.day.from_now + 30.minutes,
          duration: 30,
          status: :confirmed,
          demo: false
        )
        described_class.new(user).call
        expect(Place.exists?(place.id)).to be(true)
        expect(Visit.exists?(non_demo_visit.id)).to be(true)
      end
    end

    context 'when the user has no demo data' do
      it 'returns :no_demo_data' do
        expect(described_class.new(user).call[:status]).to eq(:no_demo_data)
      end
    end

    context 'when a point sits at a UTC/local month boundary' do
      let(:berlin_user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
      let(:utc_user)    { create(:user, settings: { 'timezone' => 'UTC' }) }
      let(:boundary_utc_ts) { Time.utc(2026, 4, 30, 22, 30).to_i }

      def seed_single_demo_point(user, timestamp)
        import = user.imports.create!(
          name: "Demo Boundary #{user.id}",
          source: :geojson,
          demo: true,
          skip_background_processing: true,
          raw_data: {}
        )
        Point.create!(
          user_id: user.id,
          import_id: import.id,
          lonlat: 'POINT(13.4 52.5)',
          timestamp: timestamp
        )
      end

      it 'extracts the month using the user timezone, not UTC' do
        seed_single_demo_point(berlin_user, boundary_utc_ts)
        seed_single_demo_point(utc_user, boundary_utc_ts)

        berlin_months = described_class.new(berlin_user).send(:collect_affected_months)
        utc_months    = described_class.new(utc_user).send(:collect_affected_months)

        expect(berlin_months).to eq([[2026, 5]])
        expect(utc_months).to eq([[2026, 4]])
      end
    end

    context 'when the user is on a non-UTC timezone' do
      let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
      before { DemoData::Importer.new(user).call }

      it 'covers every month that has a seeded Stat row' do
        affected = described_class.new(user).send(:collect_affected_months).to_set
        stat_months = user.stats.pluck(:year, :month).to_set
        expect(stat_months.subset?(affected)).to be(true)
      end
    end

    context 'when Sidekiq enqueue fails after destroy commits' do
      before { DemoData::Importer.new(user).call }

      it 'returns :destroyed and logs the enqueue failure without rolling back' do
        allow(Stats::CalculatingJob).to receive(:perform_later).and_raise(Redis::CannotConnectError, 'down')

        result = described_class.new(user).call

        expect(result[:status]).to eq(:destroyed)
        expect(user.imports.where(demo: true).count).to eq(0)
        expect(user.visits.demo.count).to eq(0)
      end
    end

    context 'callback noise during destroy' do
      before { DemoData::Importer.new(user).call }

      it 'does not enqueue Places::DeleteIfOrphanJob for every demo visit' do
        expect { described_class.new(user).call }
          .not_to have_enqueued_job(Places::DeleteIfOrphanJob)
      end

      it 'does not double-enqueue Stats::CalculatingJob via Import#recalculate_stats' do
        recalc_calls = 0
        allow_any_instance_of(Import).to receive(:recalculate_stats) { recalc_calls += 1 }
        described_class.new(user).call
        expect(recalc_calls).to eq(0)
      end
    end

    context 'when cleanup raises' do
      before { DemoData::Importer.new(user).call }

      it 'rolls back the transaction and returns :error' do
        allow_any_instance_of(Import).to receive(:destroy).and_raise(StandardError, 'boom')

        result = described_class.new(user).call

        expect(result[:status]).to eq(:error)
        expect(user.imports.where(demo: true).count).to eq(1)
        expect(user.visits.demo.count).to be > 0
        expect(user.trips.demo.count).to eq(1)
      end
    end
  end
end
