# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tagging, type: :model do
  it { is_expected.to belong_to(:taggable) }
  it { is_expected.to belong_to(:tag) }

  it { is_expected.to validate_presence_of(:taggable) }
  it { is_expected.to validate_presence_of(:tag) }

  describe 'uniqueness' do
    subject { create(:tagging) }

    it { is_expected.to validate_uniqueness_of(:tag_id).scoped_to(%i[taggable_type taggable_id]) }
  end

  it 'prevents duplicate taggings' do
    tagging = create(:tagging)
    duplicate = build(:tagging, taggable: tagging.taggable, tag: tagging.tag)

    expect(duplicate).not_to be_valid
  end
end
