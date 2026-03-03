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

    describe 'default_scope' do
      it 'excludes soft-deleted users from queries' do
        expect(User.all).to include(active_user)
        expect(User.all).not_to include(deleted_user)
      end

      it 'excludes soft-deleted users from find_by' do
        expect(User.find_by(id: deleted_user.id)).to be_nil
      end

      it 'raises RecordNotFound for soft-deleted users with find' do
        expect { User.find(deleted_user.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'includes all users when none are deleted' do
        deleted_user.update!(deleted_at: nil)
        expect(User.all).to include(active_user, deleted_user)
      end

      it 'returns empty when all users are deleted' do
        active_user.mark_as_deleted!
        expect(User.all).to be_empty
      end

      it 'can be bypassed with unscoped' do
        expect(User.unscoped.where(id: deleted_user.id)).to exist
      end
    end

    describe '.deleted' do
      it 'returns only deleted users' do
        expect(User.deleted).to include(deleted_user)
        expect(User.deleted).not_to include(active_user)
      end

      it 'returns empty when no users are deleted' do
        deleted_user.update!(deleted_at: nil)
        expect(User.deleted).not_to include(active_user, deleted_user)
      end

      it 'returns all users when all are deleted' do
        active_user.mark_as_deleted!
        expect(User.deleted.count).to eq(User.unscoped.count)
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
        expect do
          user.mark_as_deleted!
        end.to change { user.deleted_at }.from(nil).to(be_within(1.second).of(Time.current))
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

    describe '#mark_as_deleted_atomically!' do
      it 'returns true on first call' do
        expect(user.mark_as_deleted_atomically!).to be true
      end

      it 'returns false on second call' do
        user.mark_as_deleted_atomically!
        expect(user.mark_as_deleted_atomically!).to be false
      end

      it 'sets deleted_at in memory' do
        user.mark_as_deleted_atomically!
        expect(user.deleted_at).to be_present
      end

      it 'persists the deletion timestamp' do
        user.mark_as_deleted_atomically!
        expect(User.unscoped.find(user.id).deleted_at).to be_present
      end
    end

    describe '#reload' do
      it 'works after soft-deletion' do
        user.mark_as_deleted!
        expect { user.reload }.not_to raise_error
        expect(user.deleted?).to be true
      end

      it 'refreshes attributes from database' do
        User.unscoped.where(id: user.id).update_all(email: 'changed@example.com')
        user.reload
        expect(user.email).to eq('changed@example.com')
      end
    end

    describe '#destroy' do
      it 'soft deletes instead of hard deleting' do
        user_id = user.id
        user.destroy

        # Default scope excludes the user
        expect(User.where(id: user_id).count).to eq(0)
        # But user still exists in database
        expect(User.unscoped.where(id: user_id).count).to eq(1)
      end

      it 'sets deleted_at timestamp' do
        expect do
          user.destroy
        end.to change { user.deleted_at }.from(nil).to(be_present)
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
        it 'returns true' do
          expect(user.active_for_authentication?).to be true
        end
      end

      context 'when user is deleted' do
        before { user.mark_as_deleted! }

        it 'returns false' do
          expect(user.active_for_authentication?).to be false
        end
      end
    end

    describe '#inactive_message' do
      context 'when user is not deleted' do
        it 'returns default Devise message' do
          expect(user.inactive_message).not_to eq(:deleted)
        end
      end

      context 'when user is deleted' do
        before { user.mark_as_deleted! }

        it 'returns :deleted' do
          expect(user.inactive_message).to eq(:deleted)
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

      # Default scope excludes deleted user
      expect(User.find_by(id: user_id)).to be_nil

      # Deleted scope should find deleted user
      expect(User.deleted.find_by(id: user_id)).to be_present

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
