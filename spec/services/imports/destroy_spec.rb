# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Destroy do
  describe '#call' do
    let!(:user) { create(:user) }
    let!(:import) { create(:import, :with_points, user: user) }
    let(:service) { described_class.new(user, import) }

    it 'destroys the import' do
      expect { service.call }.to change { Import.count }.by(-1)
    end

    it 'destroys the points' do
      expect { service.call }.to change { Point.count }.by(-import.points.count)
    end

    it 'enqueues a BulkStatsCalculatingJob' do
      expect(Stats::BulkCalculator).to receive(:new).with(user.id).and_return(double(call: nil))

      service.call
    end

    context 'with points spanning several years' do
      let!(:import) { create(:import, user: user) }

      before do
        [Time.utc(2022, 6, 1), Time.utc(2023, 6, 1), Time.utc(2024, 6, 1)].each do |moment|
          6.times do |offset|
            create(:point, user: user, import: import, timestamp: (moment + offset.days).to_i)
          end
        end
      end

      it 'invalidates the tile cache for every year it deleted from' do
        window = [Time.utc(2022, 1, 1).to_i, Time.utc(2024, 12, 31).to_i]
        before_component = Points::TileEpoch.etag_component(user.id, *window)

        service.call

        expect(Points::TileEpoch.etag_component(user.id, *window)).not_to eq(before_component)
      end

      it 'hands the epoch one timestamp per year rather than one per deleted point' do
        received = nil
        allow(Points::TileEpoch).to receive(:bump) do |_user_id, timestamps:|
          received = timestamps
        end

        service.call

        expect(received.size).to eq(3)
      end

      it 'covers every deleted year across batches while collapsing within each' do
        stub_const('Imports::Destroy::BATCH_SIZE', 2)
        calls = []
        allow(Points::TileEpoch).to receive(:bump) do |_user_id, timestamps:|
          calls << timestamps
        end

        service.call

        calls.each do |timestamps|
          years = timestamps.map { |ts| Time.at(ts).utc.year }
          expect(years).to eq(years.uniq)
        end
        deleted_years = calls.flatten.map { |ts| Time.at(ts).utc.year }.uniq
        expect(deleted_years).to match_array([2022, 2023, 2024])
      end

      it 'bumps each completed batch before the deletion finishes' do
        stub_const('Imports::Destroy::BATCH_SIZE', 2)
        bumps = 0
        allow(Points::TileEpoch).to receive(:bump) { bumps += 1 }
        batches = 0
        allow(Point).to receive(:where).and_wrap_original do |original, *args|
          if args.first.is_a?(Hash) && args.first.key?(:id)
            batches += 1
            raise ActiveRecord::QueryCanceled if batches == 3
          end
          original.call(*args)
        end

        expect { service.call }.to raise_error(ActiveRecord::QueryCanceled)
        expect(bumps).to eq(2)
      end
    end
  end
end
