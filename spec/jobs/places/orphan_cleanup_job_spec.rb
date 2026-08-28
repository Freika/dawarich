# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::OrphanCleanupJob, type: :job do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  describe '#perform' do
    it 'deletes orphan photon places for the given user only' do
      orphan       = create(:place, user: user,  source: :photon)
      chosen       = create(:place, user: user,  source: :photon)
      manual       = create(:place, user: user,  source: :manual)
      noted        = create(:place, user: user,  source: :photon, note: 'mine')
      tagged       = create(:place, user: user,  source: :photon)
      other_orphan = create(:place, user: other, source: :photon)

      tag = create(:tag, user: user)
      tagged.tags << tag

      create(:visit, user: user, place: chosen, area: nil)

      described_class.new.perform(user.id)

      expect(Place.exists?(orphan.id)).to be(false)
      expect(Place.exists?(chosen.id)).to be(true)
      expect(Place.exists?(manual.id)).to be(true)
      expect(Place.exists?(noted.id)).to be(true)
      expect(Place.exists?(tagged.id)).to be(true)
      expect(Place.exists?(other_orphan.id)).to be(true)
    end

    it 'sweeps places referenced only by tombstoned visits and detaches them' do
      place = create(:place, user: user, source: :photon)
      tombstone = create(:visit, user: user, place: place, area: nil, deleted_at: 1.day.ago)
      kept = create(:place, user: user, source: :photon)
      create(:visit, user: user, place: kept, area: nil)

      described_class.new.perform(user.id)

      expect(Place.exists?(place.id)).to be(false)
      expect(tombstone.reload.place_id).to be_nil
      expect(Place.exists?(kept.id)).to be(true)
    end

    it 'is idempotent on second run' do
      orphan = create(:place, user: user, source: :photon)
      described_class.new.perform(user.id)
      expect { described_class.new.perform(user.id) }.not_to raise_error
      expect(Place.exists?(orphan.id)).to be(false)
    end

    it 'deletes place_visits rows referencing orphan places' do
      manual_place = create(:place, user: user, source: :manual)
      orphan       = create(:place, user: user, source: :photon)
      visit        = create(:visit, user: user, area: nil, place: manual_place)
      PlaceVisit.create!(place: orphan, visit: visit)

      described_class.new.perform(user.id)

      expect(PlaceVisit.exists?(place_id: orphan.id)).to be(false)
      expect(Place.exists?(orphan.id)).to be(false)
    end

    it 'no-ops for unknown user' do
      expect { described_class.new.perform(0) }.not_to raise_error
    end
  end
end
