# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Destroyer do
  let(:user) { create(:user) }

  describe '#call' do
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
