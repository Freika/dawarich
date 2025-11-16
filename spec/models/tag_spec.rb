# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tag, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:taggings).dependent(:destroy) }
  it { is_expected.to have_many(:places).through(:taggings) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:user) }
  
  describe 'validations' do
    subject { create(:tag) }
    
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
end
