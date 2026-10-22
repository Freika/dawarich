# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::DeleteIfOrphan do
  let(:user) { create(:user) }

  describe '.call' do
    it 'deletes a photon place with no visit, no note, no tags' do
      place = create(:place, user: user, source: :photon, note: nil)

      expect(described_class.call(place.id)).to be(true)
      expect(Place.exists?(place.id)).to be(false)
    end

    it 'returns false when place does not exist' do
      expect(described_class.call(99_999_999)).to be(false)
    end

    it 'keeps non-photon (manual) places' do
      place = create(:place, user: user, source: :manual)

      expect(described_class.call(place.id)).to be(false)
      expect(Place.exists?(place.id)).to be(true)
    end

    it 'keeps places with a note' do
      place = create(:place, user: user, source: :photon, note: 'mine')

      expect(described_class.call(place.id)).to be(false)
      expect(Place.exists?(place.id)).to be(true)
    end

    it 'keeps places referenced by any visit' do
      place = create(:place, user: user, source: :photon)
      create(:visit, user: user, place: place, area: nil)

      expect(described_class.call(place.id)).to be(false)
      expect(Place.exists?(place.id)).to be(true)
    end

    it 'deletes a photon place referenced only by hidden visits and detaches them' do
      place = create(:place, user: user, source: :photon)
      tombstone = create(:visit, user: user, place: place, area: nil, deleted_at: 1.day.ago)
      declined = create(:visit, user: user, place: place, area: nil, status: :declined)

      expect(described_class.call(place.id)).to be(true)
      expect(Place.exists?(place.id)).to be(false)
      expect(tombstone.reload.place_id).to be_nil
      expect(declined.reload.place_id).to be_nil
    end

    it 'keeps places with tags' do
      place = create(:place, user: user, source: :photon)
      tag = create(:tag, user: user)
      place.tags << tag

      expect(described_class.call(place.id)).to be(false)
      expect(Place.exists?(place.id)).to be(true)
    end

    it 'deletes the place and cascading place_visits rows even when residual ones exist' do
      place = create(:place, user: user, source: :photon)
      visit = create(:visit, user: user, area: nil, place: create(:place, user: user, source: :manual))
      PlaceVisit.create!(place: place, visit: visit)

      expect(described_class.call(place.id)).to be(true)
      expect(Place.exists?(place.id)).to be(false)
      expect(PlaceVisit.exists?(place_id: place.id)).to be(false)
    end

    it 'logs and returns false on InvalidForeignKey' do
      place = create(:place, user: user, source: :photon)
      allow_any_instance_of(Place).to receive(:delete).and_raise(ActiveRecord::InvalidForeignKey, 'fk')

      expect(Rails.logger).to receive(:warn).with(/DeleteIfOrphan/)
      expect(described_class.call(place.id)).to be(false)
    end
  end
end
