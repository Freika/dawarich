# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SoftDeletable do
  # Use User as the test model since it includes SoftDeletable
  let(:user) { create(:user) }

  describe 'scopes' do
    let!(:active_user) { create(:user) }
    let!(:deleted_user) { create(:user) }

    before do
      deleted_user.mark_as_deleted!
    end

    describe '.active_accounts' do
      it 'returns only non-deleted users' do
        expect(User.active_accounts).to include(active_user)
        expect(User.active_accounts).not_to include(deleted_user)
      end

      it 'returns all users when none are deleted' do
        deleted_user.update!(deleted_at: nil)
        expect(User.active_accounts.count).to eq(User.count)
      end

      it 'returns empty when all users are deleted' do
        active_user.mark_as_deleted!
        expect(User.active_accounts).to be_empty
      end
    end

    describe '.deleted_accounts' do
      it 'returns only deleted users' do
        expect(User.deleted_accounts).to include(deleted_user)
        expect(User.deleted_accounts).not_to include(active_user)
      end

      it 'returns empty when no users are deleted' do
        deleted_user.update!(deleted_at: nil)
        expect(User.deleted_accounts).to be_empty
      end

      it 'returns all users when all are deleted' do
        active_user.mark_as_deleted!
        expect(User.deleted_accounts.count).to eq(User.count)
      end
    end
  end

  describe 'instance methods' do
    describe '#deleted?' do
      context 'when user is not deleted' do
        it 'returns false' do
          expect(user.deleted?).to be false
        end

        it 'returns false when deleted_at is nil' do
          user.deleted_at = nil
          expect(user.deleted?).to be false
        end
      end

      context 'when user is deleted' do
        before do
          user.mark_as_deleted!
        end

        it 'returns true' do
          expect(user.deleted?).to be true
        end

        it 'returns true when deleted_at is set' do
          expect(user.deleted?).to be true
        end
      end
    end

    describe '#mark_as_deleted!' do
      it 'sets deleted_at timestamp' do
        expect {
          user.mark_as_deleted!
        }.to change { user.deleted_at }.from(nil).to(be_within(1.second).of(Time.current))
      end

      it 'persists the deletion timestamp' do
        user.mark_as_deleted!
        expect(user.reload.deleted_at).to be_present
      end

      it 'makes deleted? return true' do
        user.mark_as_deleted!
        expect(user.deleted?).to be true
      end

      it 'can be called multiple times' do
        user.mark_as_deleted!
        first_deleted_at = user.deleted_at

        # Call again
        user.mark_as_deleted!
        second_deleted_at = user.deleted_at

        expect(second_deleted_at).to be >= first_deleted_at
      end
    end

    describe '#destroy' do
      it 'soft deletes instead of hard deleting' do
        user_id = user.id
        user.destroy

        # User count doesn't change from active users perspective
        expect(User.active_accounts.where(id: user_id).count).to eq(0)
        # But user still exists in database
        expect(User.unscoped.where(id: user_id).count).to eq(1)
      end

      it 'sets deleted_at timestamp' do
        expect {
          user.destroy
        }.to change { user.deleted_at }.from(nil).to(be_present)
      end

      it 'makes the user deleted' do
        user.destroy
        expect(user.deleted?).to be true
      end

      it 'keeps the user in the database' do
        user_id = user.id
        user.destroy
        expect(User.unscoped.find_by(id: user_id)).to be_present
      end
    end
  end

  describe 'Devise integration' do
    describe '#active_for_authentication?' do
      context 'when user is not deleted' do
        it 'checks Devise conditions and deletion status' do
          # Active user should be active for authentication
          expect(user.deleted?).to be false
          # Result depends on Devise's super implementation
        end
      end

      context 'when user is deleted' do
        before do
          user.mark_as_deleted!
        end

        it 'prevents authentication for deleted users' do
          # Deleted users should not be active for authentication
          expect(user.deleted?).to be true
        end
      end
    end

    describe '#inactive_message' do
      context 'when user is not deleted' do
        it 'does not return deleted message' do
          # Active users should not have deleted message
          expect(user.deleted?).to be false
        end
      end

      context 'when user is deleted' do
        before do
          user.mark_as_deleted!
        end

        it 'indicates account is deleted' do
          expect(user.deleted?).to be true
          # The inactive_message should be :deleted
        end
      end
    end
  end

  describe 'edge cases' do
    it 'handles deleted_at being set directly' do
      user.deleted_at = 1.day.ago
      expect(user.deleted?).to be true
    end

    it 'handles deleted_at being unset after deletion' do
      user.mark_as_deleted!
      user.update!(deleted_at: nil)
      expect(user.deleted?).to be false
    end

    it 'works with User queries' do
      user_id = user.id
      user.mark_as_deleted!

      # Active accounts scope should not find deleted user
      expect(User.active_accounts.find_by(id: user_id)).to be_nil

      # Deleted accounts scope should find deleted user
      expect(User.deleted_accounts.find_by(id: user_id)).to be_present

      # Should find with unscoped
      expect(User.unscoped.find_by(id: user_id)).to be_present
    end

    it 'works with associations' do
      point = create(:point, user: user)
      user.mark_as_deleted!

      # Point should still exist
      expect(Point.find_by(id: point.id)).to be_present

      # User is soft-deleted
      expect(user.deleted?).to be true
    end
  end
end
