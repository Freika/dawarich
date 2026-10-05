# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Destroyer do
  let(:user) { create(:user) }

  describe '#call' do
    it 'returns destroyed points and schedules months in ascending id order despite descending insertion' do
      high = Point.maximum(:id).to_i + 100
      june = Time.zone.local(2024, 6, 2, 9).to_i
      july = Time.zone.local(2024, 7, 1, 8).to_i
      create(:point, user: user, track: nil, id: high, timestamp: june)
      create(:point, user: user, track: nil, id: high - 1, timestamp: july)
      ActiveRecord::Base.connection.execute('SET LOCAL enable_indexscan=off')
      ActiveRecord::Base.connection.execute('SET LOCAL enable_bitmapscan=off')

      destroyed = described_class.new(user, [high, high - 1]).call

      expect(destroyed.map(&:id)).to eq([high - 1, high])
      expect(destroyed.map(&:timestamp)).to eq([july, june])
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Stats::CalculatingJob }
      expect(jobs.map { |job| job[:args] }).to eq([[user.id, 2024, 7], [user.id, 2024, 6]])
    end

    context 'with tracked and untracked points across months' do
      let(:track1) { create(:track, user: user) }
      let(:track2) { create(:track, user: user) }
      let!(:may_point) do
        create(:point, user: user, track: track1, timestamp: Time.zone.local(2024, 5, 10, 12).to_i)
      end
      let!(:may_point_same_track) do
        create(:point, user: user, track: track1, timestamp: Time.zone.local(2024, 5, 10, 13).to_i)
      end
      let!(:june_point) do
        create(:point, user: user, track: track2, timestamp: Time.zone.local(2024, 6, 2, 9).to_i)
      end
      let!(:untracked_point) do
        create(:point, user: user, track: nil, timestamp: Time.zone.local(2024, 7, 1, 8).to_i)
      end
      let(:point_ids) { [may_point.id, may_point_same_track.id, june_point.id, untracked_point.id] }

      it 'destroys the points' do
        expect { described_class.new(user, point_ids).call }.to change { user.points.count }.by(-4)
      end

      it 'decrements the points counter' do
        user.update_column(:points_count, 10)

        expect { described_class.new(user, point_ids).call }
          .to change { user.reload.points_count }.by(-4)
      end

      it 'enqueues one track recalculation per distinct affected track' do
        expect { described_class.new(user, point_ids).call }
          .to have_enqueued_job(Tracks::RecalculateJob).with(track1.id).exactly(:once)
          .and have_enqueued_job(Tracks::RecalculateJob).with(track2.id).exactly(:once)
      end

      it 'enqueues one stats recalculation per distinct affected month' do
        expect { described_class.new(user, point_ids).call }
          .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 5).exactly(:once)
          .and have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 6).exactly(:once)
          .and have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 7).exactly(:once)
      end

      it 'rebuilds achievement dwell from the oldest deleted point' do
        clear_achievement_checks(user.id)

        expect { described_class.new(user, point_ids).call }
          .to have_enqueued_job(Achievements::CheckJob).with(user.id)
        expect(Achievements::PendingChecks.read(user.id).first).to eq(may_point.timestamp)
      end

      it 'returns the destroyed points' do
        expect(described_class.new(user, point_ids).call.map(&:id)).to match_array(point_ids)
      end
    end

    context 'with points belonging to another user' do
      let(:other_user) { create(:user) }
      let!(:own_point) { create(:point, user: user, track: nil) }
      let!(:foreign_point) { create(:point, user: other_user, track: nil) }

      it 'only destroys points of the given user' do
        expect { described_class.new(user, [own_point.id, foreign_point.id]).call }
          .to change { user.points.count }.by(-1)
          .and change { other_user.points.count }.by(0)
      end
    end

    context 'when deleting the current achievement cursor' do
      let(:base_ts) { DateTime.new(2026, 1, 1).to_i }
      let(:germany_geom) { 'MULTIPOLYGON (((11 48, 11 49, 12 49, 12 48, 11 48)))' }
      let!(:region) { create(:region, code: 'DE-BY', geom: germany_geom) }
      let!(:country) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU', geom: germany_geom) }
      let!(:points) do
        8.times.map do |index|
          create(:point, user: user, longitude: 11.5, latitude: 48.5,
                         timestamp: base_ts + (index * 600), country_id: country.id)
        end
      end

      before do
        clear_achievement_checks(user.id)
        Achievements::RegionSetChecker.new(user, notify: false).call
      end

      it 'executes an exact rebuild when the deleted timestamp equals the cursor' do
        progress = Achievements::Progress.find_by!(user: user, achievement_key: 'exploration')
        expect(progress.state['dwell']['DE-BY']).to eq(4_200)

        perform_enqueued_jobs(only: Achievements::CheckJob) do
          described_class.new(user, points.last.id).call
        end

        expect(progress.reload.state['dwell']['DE-BY']).to eq(3_600)
      end
    end

    context 'with no matching points' do
      it 'does not change the points counter' do
        expect { described_class.new(user, [-1]).call }.not_to(change { user.reload.points_count })
      end

      it 'enqueues no jobs' do
        expect { described_class.new(user, [-1]).call }.not_to have_enqueued_job
      end
    end
  end
end
