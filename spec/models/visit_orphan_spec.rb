# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visit, type: :model do
  let(:user) { create(:user) }

  describe 'associations' do
    it 'is nullified (place_id set to NULL) when associated place is destroyed' do
      place = create(:place, user: user)
      visit = create(:visit, user: user, place: place)

      expect { place.destroy }.not_to change(Visit, :count)
      expect(visit.reload.place_id).to be_nil
    end

    it 'is destroyed when associated area is destroyed' do
      area = create(:area, user: user)
      create(:visit, user: user, area: area, place: nil)
      expect { area.destroy }.to change(Visit, :count).by(-1)
    end
  end

  describe 'validations' do
    it 'can be created without a place or area' do
      visit = build(:visit, user: user, place: nil, area: nil)
      expect(visit).to be_valid
      expect(visit.save).to be true
    end
  end
end
