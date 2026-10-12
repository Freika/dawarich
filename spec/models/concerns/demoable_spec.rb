# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Demoable do
  let(:user) { create(:user) }

  describe '.demo scope' do
    it 'returns only records where demo is true' do
      demo_visit = create(:visit, user: user, demo: true)
      real_visit = create(:visit, user: user, demo: false)

      expect(Visit.demo).to include(demo_visit)
      expect(Visit.demo).not_to include(real_visit)
    end
  end

  describe '#adopt!' do
    it 'flips demo to false' do
      visit = create(:visit, user: user, demo: true)
      visit.adopt!
      expect(visit.reload.demo).to be(false)
    end

    it 'bumps updated_at when flipping' do
      visit = create(:visit, user: user, demo: true)
      visit.update_columns(updated_at: 1.week.ago)
      original = visit.reload.updated_at

      visit.adopt!

      expect(visit.reload.updated_at).to be > original
    end

    it 'is a no-op when already non-demo' do
      visit = create(:visit, user: user, demo: false)
      expect { visit.adopt! }.not_to(change { visit.reload.updated_at })
    end
  end

  describe 'Visit adoption propagation' do
    let(:place) { create(:place, demo: true) }
    let(:tag) { create(:tag, user: user, demo: true) }

    it 'adopts demo place when a non-demo visit references it' do
      create(:visit, user: user, place: place, demo: false)
      expect(place.reload.demo).to be(false)
    end

    it 'adopts demo tags attached to the visited place when visit is real' do
      place.tags << tag
      create(:visit, user: user, place: place, demo: false)
      expect(tag.reload.demo).to be(false)
    end

    it 'does NOT propagate when the visit itself is demo' do
      create(:visit, user: user, place: place, demo: true)
      expect(place.reload.demo).to be(true)
    end

    it 'propagates when an existing demo visit is updated to non-demo' do
      visit = create(:visit, user: user, place: place, demo: true)
      visit.adopt!
      expect(place.reload.demo).to be(false)
    end

    it 'propagates when an existing real visit is moved to a demo place' do
      other_place = create(:place, user: user, demo: false)
      visit = create(:visit, user: user, place: other_place, demo: false)
      visit.update!(place: place)
      expect(place.reload.demo).to be(false)
    end
  end
end
