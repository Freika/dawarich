# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tag, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:taggings).dependent(:destroy) }
  it { is_expected.to have_many(:places).through(:taggings) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:icon).is_at_most(10) }
  it { is_expected.to allow_value(nil).for(:icon) }

  describe 'validations' do
    subject { create(:tag) }

    it {
      is_expected.to validate_numericality_of(:privacy_radius_meters)
        .is_greater_than(0).is_less_than_or_equal_to(5000).allow_nil
    }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id) }

    it 'validates hex color' do
      expect(build(:tag, color: '#FF5733')).to be_valid
      expect(build(:tag, color: 'invalid')).not_to be_valid
      expect(build(:tag, color: nil)).to be_valid
    end
  end

  describe 'scopes' do
    let!(:tag1) { create(:tag, name: 'A') }
    let!(:tag2) { create(:tag, name: 'B', user: tag1.user) }

    it '.for_user' do
      expect(Tag.for_user(tag1.user)).to contain_exactly(tag1, tag2)
    end

    it '.ordered' do
      expect(Tag.for_user(tag1.user).ordered).to eq([tag1, tag2])
    end
  end

  describe '.home_tagged_place' do
    let(:user) { create(:user) }

    def tag_place(tag, name, **attrs)
      create(:place, user: tag.user, name:, **attrs).tap { |place| Tagging.create!(tag:, taggable: place) }
    end

    it 'finds a Place tagged Home in any letter case' do
      tag = create(:tag, user:, name: 'HOME')
      place = tag_place(tag, 'Casa')

      expect(Tag.home_tagged_place(user)).to eq([tag, place])
    end

    it 'looks past a Home-named tag that has no live Place' do
      tag_place(create(:tag, user:, name: 'Home'), 'Old flat', archived_at: Time.current)
      zuhause = create(:tag, user:, name: 'Zuhause')
      place = tag_place(zuhause, 'Wohnung')

      expect(Tag.home_tagged_place(user)).to eq([zuhause, place])
    end

    it 'ignores Home tags of other users' do
      tag_place(create(:tag, name: 'Home'), 'Not mine')

      expect(Tag.home_tagged_place(user)).to be_nil
    end
  end
end
