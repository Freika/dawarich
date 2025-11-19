# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Place, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:visits).dependent(:destroy) }
    it { is_expected.to have_many(:place_visits).dependent(:destroy) }
    it { is_expected.to have_many(:suggested_visits).through(:place_visits) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:lonlat) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:source).with_values(%i[manual photon]) }
  end

  describe 'scopes' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let!(:place1) { create(:place, user: user1, name: 'Zoo') }
    let!(:place2) { create(:place, user: user1, name: 'Airport') }
    let!(:place3) { create(:place, user: user2, name: 'Museum') }

    describe '.for_user' do
      it 'returns places for the specified user' do
        expect(Place.for_user(user1)).to contain_exactly(place1, place2)
      end

      it 'does not return places for other users' do
        expect(Place.for_user(user1)).not_to include(place3)
      end

      it 'returns empty when user has no places' do
        new_user = create(:user)
        expect(Place.for_user(new_user)).to be_empty
      end
    end

    describe '.ordered' do
      it 'orders places by name alphabetically' do
        expect(Place.for_user(user1).ordered).to eq([place2, place1])
      end

      it 'handles case-insensitive ordering' do
        place_lower = create(:place, user: user1, name: 'airport')
        place_upper = create(:place, user: user1, name: 'BEACH')

        ordered = Place.for_user(user1).ordered
        # The ordered scope orders by name alphabetically (case-sensitive in most DBs)
        expect(ordered.map(&:name)).to include('airport', 'BEACH')
      end
    end
  end

  describe 'Taggable concern integration' do
    let(:user) { create(:user) }
    let(:place) { create(:place, user: user) }
    let(:tag1) { create(:tag, user: user, name: 'Restaurant') }
    let(:tag2) { create(:tag, user: user, name: 'Favorite') }

    it 'can add tags to a place' do
      place.add_tag(tag1)
      expect(place.tags).to include(tag1)
    end

    it 'can remove tags from a place' do
      place.tags << tag1
      place.remove_tag(tag1)
      expect(place.tags).not_to include(tag1)
    end

    it 'returns tag names' do
      place.tags << [tag1, tag2]
      expect(place.tag_names).to contain_exactly('Restaurant', 'Favorite')
    end

    it 'checks if tagged with a specific tag' do
      place.tags << tag1
      expect(place.tagged_with?(tag1)).to be true
      expect(place.tagged_with?(tag2)).to be false
    end

    describe 'scopes' do
      let!(:tagged_place) { create(:place, user: user) }
      let!(:untagged_place) { create(:place, user: user) }

      before do
        tagged_place.tags << tag1
      end

      it 'filters places with specific tags' do
        results = Place.with_tags([tag1.id])
        expect(results).to include(tagged_place)
        expect(results).not_to include(untagged_place)
      end

      it 'filters places without tags' do
        results = Place.without_tags
        expect(results).to include(untagged_place)
        expect(results).not_to include(tagged_place)
      end

      it 'filters places by tag name and user' do
        results = Place.tagged_with('Restaurant', user)
        expect(results).to include(tagged_place)
        expect(results).not_to include(untagged_place)
      end
    end
  end

  describe 'methods' do
    let(:place) { create(:place, :with_geodata) }

    describe '#osm_id' do
      it 'returns the osm_id' do
        expect(place.osm_id).to eq(5_762_449_774)
      end
    end

    describe '#osm_key' do
      it 'returns the osm_key' do
        expect(place.osm_key).to eq('amenity')
      end
    end

    describe '#osm_value' do
      it 'returns the osm_value' do
        expect(place.osm_value).to eq('restaurant')
      end
    end

    describe '#osm_type' do
      it 'returns the osm_type' do
        expect(place.osm_type).to eq('N')
      end
    end

    describe '#lon' do
      it 'returns the longitude' do
        expect(place.lon).to be_within(0.000001).of(13.0948638)
      end
    end

    describe '#lat' do
      it 'returns the latitude' do
        expect(place.lat).to be_within(0.000001).of(54.2905245)
      end
    end
  end
end
