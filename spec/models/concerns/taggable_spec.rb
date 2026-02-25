# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Taggable do
  # Use Place as the test model since it includes Taggable
  let(:user) { create(:user) }
  let(:tag1) { create(:tag, user: user, name: 'Home') }
  let(:tag2) { create(:tag, user: user, name: 'Work') }
  let(:tag3) { create(:tag, user: user, name: 'Gym') }

  describe 'associations' do
    it { expect(Place.new).to have_many(:taggings).dependent(:destroy) }
    it { expect(Place.new).to have_many(:tags).through(:taggings) }
  end

  describe 'scopes' do
    let!(:place1) { create(:place, user: user) }
    let!(:place2) { create(:place, user: user) }
    let!(:place3) { create(:place, user: user) }

    before do
      place1.tags << [tag1, tag2]
      place2.tags << tag1
      # place3 has no tags
    end

    describe '.with_tags' do
      it 'returns places with any of the specified tag IDs' do
        results = Place.for_user(user).with_tags([tag1.id])
        expect(results).to contain_exactly(place1, place2)
      end

      it 'returns places with multiple tag IDs' do
        results = Place.for_user(user).with_tags([tag1.id, tag2.id])
        expect(results).to contain_exactly(place1, place2)
      end

      it 'returns distinct results when place has multiple matching tags' do
        results = Place.for_user(user).with_tags([tag1.id, tag2.id])
        expect(results.count).to eq(2)
        expect(results).to contain_exactly(place1, place2)
      end

      it 'returns empty when no places have the specified tags' do
        results = Place.for_user(user).with_tags([tag3.id])
        expect(results).to be_empty
      end

      it 'accepts a single tag ID' do
        results = Place.for_user(user).with_tags(tag1.id)
        expect(results).to contain_exactly(place1, place2)
      end
    end

    describe '.without_tags' do
      it 'returns only places without any tags' do
        results = Place.for_user(user).without_tags
        expect(results).to contain_exactly(place3)
      end

      it 'returns empty when all places have tags' do
        place3.tags << tag3
        results = Place.for_user(user).without_tags
        expect(results).to be_empty
      end

      it 'returns all places when none have tags' do
        place1.tags.clear
        place2.tags.clear
        results = Place.for_user(user).without_tags
        expect(results).to contain_exactly(place1, place2, place3)
      end
    end

    describe '.tagged_with' do
      it 'returns places tagged with the specified tag name' do
        results = Place.for_user(user).tagged_with('Home', user)
        expect(results).to contain_exactly(place1, place2)
      end

      it 'returns distinct results' do
        results = Place.for_user(user).tagged_with('Home', user)
        expect(results.count).to eq(2)
      end

      it 'returns empty when no places have the tag name' do
        results = Place.for_user(user).tagged_with('NonExistent', user)
        expect(results).to be_empty
      end

      it 'filters by user' do
        other_user = create(:user)
        other_tag = create(:tag, user: other_user, name: 'Home')
        other_place = create(:place, user: other_user)
        other_place.tags << other_tag

        results = Place.for_user(user).tagged_with('Home', user)
        expect(results).to contain_exactly(place1, place2)
        expect(results).not_to include(other_place)
      end
    end
  end

  describe 'instance methods' do
    let(:place) { create(:place, user: user) }

    describe '#add_tag' do
      it 'adds a tag to the record' do
        expect do
          place.add_tag(tag1)
        end.to change { place.tags.count }.by(1)
      end

      it 'does not add duplicate tags' do
        place.add_tag(tag1)
        expect do
          place.add_tag(tag1)
        end.not_to(change { place.tags.count })
      end

      it 'adds the correct tag' do
        place.add_tag(tag1)
        expect(place.tags).to include(tag1)
      end

      it 'can add multiple different tags' do
        place.add_tag(tag1)
        place.add_tag(tag2)
        expect(place.tags).to contain_exactly(tag1, tag2)
      end
    end

    describe '#remove_tag' do
      before do
        place.tags << [tag1, tag2]
      end

      it 'removes a tag from the record' do
        expect do
          place.remove_tag(tag1)
        end.to change { place.tags.count }.by(-1)
      end

      it 'removes the correct tag' do
        place.remove_tag(tag1)
        expect(place.tags).not_to include(tag1)
        expect(place.tags).to include(tag2)
      end

      it 'does nothing when tag is not present' do
        expect do
          place.remove_tag(tag3)
        end.not_to(change { place.tags.count })
      end
    end

    describe '#tag_names' do
      it 'returns an empty array when no tags' do
        expect(place.tag_names).to eq([])
      end

      it 'returns array of tag names' do
        place.tags << [tag1, tag2]
        expect(place.tag_names).to contain_exactly('Home', 'Work')
      end

      it 'returns tag names in database order' do
        place.tags << tag2
        place.tags << tag1
        # Order depends on taggings created_at
        expect(place.tag_names).to be_an(Array)
        expect(place.tag_names.size).to eq(2)
      end
    end

    describe '#tagged_with?' do
      before do
        place.tags << tag1
      end

      it 'returns true when tagged with the specified tag' do
        expect(place.tagged_with?(tag1)).to be true
      end

      it 'returns false when not tagged with the specified tag' do
        expect(place.tagged_with?(tag2)).to be false
      end

      it 'returns false when place has no tags' do
        place.tags.clear
        expect(place.tagged_with?(tag1)).to be false
      end
    end
  end
end
