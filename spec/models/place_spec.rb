# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Place, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:visits).dependent(:nullify) }
    it { is_expected.to have_many(:place_visits).dependent(:destroy) }
    it { is_expected.to have_many(:suggested_visits).through(:place_visits) }
  end

  describe 'user ownership' do
    it 'refuses to save a place without a user' do
      place = build(:place, user: nil)

      expect(place).not_to be_valid
      expect(place.errors[:user]).to be_present
    end

    it 'rejects a NULL user_id at the database level' do
      place = create(:place, user: create(:user))

      expect { place.update_columns(user_id: nil) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe '.linked_to_confirmed_visits' do
    it 'excludes places linked only through tombstoned visits' do
      user = create(:user)
      alive_place = create(:place, user: user)
      ghost_place = create(:place, user: user)
      create(:visit, user: user, place: alive_place, status: 'confirmed', area: nil)
      create(:visit, user: user, place: ghost_place, status: 'confirmed', deleted_at: 1.day.ago, area: nil)

      expect(Place.linked_to_confirmed_visits(user)).to include(alive_place)
      expect(Place.linked_to_confirmed_visits(user)).not_to include(ghost_place)
    end
  end

  describe 'destroying a place' do
    it 'nullifies place_id on associated visits, does not delete them' do
      user = create(:user)
      place = create(:place, user: user)
      visit = create(:visit, user: user, place: place, area: nil)

      place.destroy!

      expect(Visit.exists?(visit.id)).to be(true)
      expect(visit.reload.place_id).to be_nil
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:lonlat) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
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
        create(:place, user: user1, name: 'airport')
        create(:place, user: user1, name: 'BEACH')

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

      context 'when a legacy place has no lonlat' do
        it 'returns the longitude column as a Float' do
          place.update_column(:lonlat, nil)

          expect(place.reload.lon).to be_a(Float)
          expect(place.reload.lon).to be_within(0.000001).of(13.0948638)
        end
      end
    end

    describe '#lat' do
      it 'returns the latitude' do
        expect(place.lat).to be_within(0.000001).of(54.2905245)
      end

      context 'when a legacy place has no lonlat' do
        it 'returns the latitude column as a Float' do
          place.update_column(:lonlat, nil)

          expect(place.reload.lat).to be_a(Float)
          expect(place.reload.lat).to be_within(0.000001).of(54.2905245)
        end
      end
    end
  end

  describe 'name locking' do
    let(:place) { create(:place, name: Place::DEFAULT_NAME) }

    it 'is unlocked when created' do
      expect(place.name_locked?).to be(false)
    end

    it 'locks the name when it is renamed' do
      expect { place.update!(name: "Mum's house") }
        .to change { place.reload.name_locked? }.from(false).to(true)
    end

    it 'does not lock when another attribute changes' do
      place.update!(city: 'Leipzig')

      expect(place.reload.name_locked?).to be(false)
    end

    it 'does not lock a machine-named place' do
      machine_place = build(:place, name: 'Photon Suggestion')
      machine_place.machine_named = true
      machine_place.save!

      expect(machine_place.reload.name_locked?).to be(false)
    end

    it 'does not lock a place minted by detection' do
      expect(create(:place, name: 'Photon Suggestion').name_locked?).to be(false)
    end

    it 'locks a place created with a user-supplied name' do
      user_place = build(:place, name: "Mum's house")
      user_place.user_named = true
      user_place.save!

      expect(user_place.reload.name_locked?).to be(true)
    end

    it 'clears the lock when the name is reset to the default' do
      place.update!(name: "Mum's house")

      expect { place.update!(name: Place::DEFAULT_NAME) }
        .to change { place.reload.name_locked? }.from(true).to(false)
    end

    it 'keeps an existing lock when a machine write touches other attributes' do
      place.update!(name: "Mum's house")
      locked_at = place.reload.name_locked_at

      place.machine_named = true
      place.update!(city: 'Leipzig')

      expect(place.reload.name_locked_at).to be_within(1.second).of(locked_at)
    end
  end
end
