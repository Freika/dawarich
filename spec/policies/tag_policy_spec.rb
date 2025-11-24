# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TagPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:tag) { create(:tag, user: user) }
  let(:other_tag) { create(:tag, user: other_user) }

  describe 'index?' do
    it 'allows any authenticated user' do
      expect(TagPolicy.new(user, Tag).index?).to be true
    end
  end

  describe 'create? and new?' do
    it 'allows any authenticated user to create' do
      new_tag = user.tags.build
      expect(TagPolicy.new(user, new_tag).create?).to be true
      expect(TagPolicy.new(user, new_tag).new?).to be true
    end
  end

  describe 'show?, edit?, update?, destroy?' do
    context 'when user owns the tag' do
      it 'allows all actions' do
        policy = TagPolicy.new(user, tag)
        expect(policy.show?).to be true
        expect(policy.edit?).to be true
        expect(policy.update?).to be true
        expect(policy.destroy?).to be true
      end
    end

    context 'when user does not own the tag' do
      it 'denies all actions' do
        policy = TagPolicy.new(user, other_tag)
        expect(policy.show?).to be false
        expect(policy.edit?).to be false
        expect(policy.update?).to be false
        expect(policy.destroy?).to be false
      end
    end
  end

  describe 'Scope' do
    let!(:user_tags) { create_list(:tag, 3, user: user) }
    let!(:other_tags) { create_list(:tag, 2, user: other_user) }

    it 'returns only user-owned tags' do
      scope = TagPolicy::Scope.new(user, Tag).resolve
      expect(scope).to match_array(user_tags)
      expect(scope).not_to include(*other_tags)
    end
  end
end
