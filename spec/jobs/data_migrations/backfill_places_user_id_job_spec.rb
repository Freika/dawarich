# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPlacesUserIdJob, type: :job do
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  def orphan_place
    create(:place, user: nil)
  end

  describe '#perform' do
    it 'assigns the user with the most visits via place_visits join table' do
      place = orphan_place
      v1 = create(:visit, user: user_a, started_at: 3.days.ago)
      v2 = create(:visit, user: user_a, started_at: 2.days.ago)
      v3 = create(:visit, user: user_b, started_at: 1.day.ago)
      create(:place_visit, place: place, visit: v1)
      create(:place_visit, place: place, visit: v2)
      create(:place_visit, place: place, visit: v3)

      described_class.perform_now

      expect(place.reload.user_id).to eq(user_a.id)
    end

    it 'assigns via visits.place_id direct link when no place_visits row exists' do
      place = orphan_place
      create(:visit, user: user_b, place: place, started_at: 1.hour.ago)

      described_class.perform_now

      expect(place.reload.user_id).to eq(user_b.id)
    end

    it 'breaks count ties by most recent ts (max started_at)' do
      place = orphan_place
      v_old_a = create(:visit, user: user_a, started_at: 5.days.ago)
      v_newer_b = create(:visit, user: user_b, started_at: 1.day.ago)
      create(:place_visit, place: place, visit: v_old_a)
      create(:place_visit, place: place, visit: v_newer_b)

      described_class.perform_now

      expect(place.reload.user_id).to eq(user_b.id)
    end

    it 'breaks count and ts ties by lowest user_id' do
      place = orphan_place
      now = Time.current
      v_a = create(:visit, user: user_a, started_at: now)
      v_b = create(:visit, user: user_b, started_at: now)
      create(:place_visit, place: place, visit: v_a)
      create(:place_visit, place: place, visit: v_b)

      described_class.perform_now

      winner = [user_a.id, user_b.id].min
      expect(place.reload.user_id).to eq(winner)
    end

    it 'deletes orphan places that have no visits at all' do
      place = orphan_place

      described_class.perform_now

      expect(Place.where(id: place.id)).not_to exist
    end

    it 'leaves places that already have user_id untouched' do
      place = create(:place, user: user_a)

      expect { described_class.perform_now }.not_to(change { place.reload.attributes })
    end

    it 'is idempotent: second run after backfill is a no-op' do
      place = orphan_place
      create(:place_visit, place: place, visit: create(:visit, user: user_a))

      described_class.perform_now
      expect(place.reload.user_id).to eq(user_a.id)
      first_updated_at = place.reload.updated_at

      described_class.perform_now

      expect(place.reload.user_id).to eq(user_a.id)
      expect(place.reload.updated_at).to eq(first_updated_at)
    end

    it 'processes all places across multiple batches when batch_size is small' do
      place_1 = orphan_place
      place_2 = orphan_place
      place_3 = orphan_place
      create(:place_visit, place: place_1, visit: create(:visit, user: user_a))
      create(:place_visit, place: place_2, visit: create(:visit, user: user_b))
      # place_3 has no visits -> orphan delete branch

      described_class.perform_now(batch_size: 1)

      expect(place_1.reload.user_id).to eq(user_a.id)
      expect(place_2.reload.user_id).to eq(user_b.id)
      expect(Place.where(id: place_3.id)).not_to exist
    end
  end
end
