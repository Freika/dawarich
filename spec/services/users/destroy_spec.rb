# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Destroy do
  describe '#call' do
    let(:user) { create(:user) }
    let(:service) { described_class.new(user) }

    before do
      user.mark_as_deleted!
    end

    context 'with minimal user data' do
      it 'hard deletes the user record' do
        expect { service.call }.to change(User, :count).by(-1)
      end

      it 'returns true on success' do
        expect(service.call).to be true
      end

      it 'logs the deletion' do
        allow(Rails.logger).to receive(:info)

        service.call

        expect(Rails.logger).to have_received(:info).with(/User \d+ \(.+\) and all associated data deleted/)
      end
    end

    context 'with associated records without foreign key constraints' do
      let!(:points) { create_list(:point, 5, user:) }
      let!(:import) { create(:import, user:) }
      let!(:stat) { create(:stat, user:, year: 2024, month: 1) }
      let!(:place) { create(:place, user:) }
      let!(:trip) { create(:trip, user:) }
      let!(:notification) { create(:notification, user:) }

      it 'deletes all points' do
        user_id = user.id
        service.call
        expect(Point.where(user_id: user_id).count).to eq(0)
      end

      it 'deletes all imports' do
        user_id = user.id
        service.call
        expect(Import.where(user_id: user_id).count).to eq(0)
      end

      it 'deletes all stats' do
        user_id = user.id
        service.call
        expect(Stat.where(user_id: user_id).count).to eq(0)
      end

      it 'deletes all places' do
        user_id = user.id
        service.call
        expect(Place.where(user_id: user_id).count).to eq(0)
      end

      it 'deletes all trips' do
        user_id = user.id
        service.call
        expect(Trip.where(user_id: user_id).count).to eq(0)
      end

      it 'deletes all notifications' do
        user_id = user.id
        service.call
        expect(Notification.where(user_id: user_id).count).to eq(0)
      end

      it 'performs all deletions in a transaction' do
        # Mock error before user deletion
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)
        allow_any_instance_of(described_class).to receive(:cancel_scheduled_jobs)
        allow(Point).to receive(:where).and_call_original

        # This will cause the transaction to fail
        allow(user).to receive(:delete).and_raise(StandardError, 'Database error')

        expect { service.call }.to raise_error(StandardError)
      end
    end

    context 'with scheduled jobs' do
      it 'attempts to cancel scheduled jobs for the user' do
        allow(Rails.logger).to receive(:info)

        service.call

        expect(Rails.logger).to have_received(:info).with(/Cancelled \d+ scheduled jobs for user #{user.id}/)
      end

      context 'when job cancellation fails' do
        before do
          allow(Sidekiq::ScheduledSet).to receive(:new).and_raise(StandardError, 'Redis error')
        end

        it 'logs a warning but continues deletion' do
          allow(Rails.logger).to receive(:warn)
          allow(Rails.logger).to receive(:info)
          allow(Rails.logger).to receive(:error)
          allow(ExceptionReporter).to receive(:call)

          expect { service.call }.not_to raise_error

          expect(Rails.logger).to have_received(:warn).with(/Failed to cancel scheduled jobs/)
          expect(ExceptionReporter).to have_received(:call)
        end
      end
    end

    context 'with cache cleanup' do
      before do
        # Populate cache with user data
        Rails.cache.write("dawarich/user_#{user.id}_countries_visited", ['US', 'CA'])
        Rails.cache.write("dawarich/user_#{user.id}_cities_visited", ['NYC', 'SF'])
        Rails.cache.write("dawarich/user_#{user.id}_total_distance", 1000)
        Rails.cache.write("dawarich/user_#{user.id}_years_tracked", [2023, 2024])
      end

      it 'clears all user-specific cache keys' do
        service.call

        expect(Rails.cache.read("dawarich/user_#{user.id}_countries_visited")).to be_nil
        expect(Rails.cache.read("dawarich/user_#{user.id}_cities_visited")).to be_nil
        expect(Rails.cache.read("dawarich/user_#{user.id}_total_distance")).to be_nil
        expect(Rails.cache.read("dawarich/user_#{user.id}_years_tracked")).to be_nil
      end

      it 'logs cache cleanup' do
        allow(Rails.logger).to receive(:info)

        service.call

        expect(Rails.logger).to have_received(:info).with("Cleared cache for user #{user.id}")
      end

      context 'when cache cleanup fails' do
        before do
          allow(Rails.cache).to receive(:delete).and_raise(StandardError, 'Cache error')
        end

        it 'logs a warning but completes deletion' do
          allow(Rails.logger).to receive(:warn)

          expect { service.call }.not_to raise_error

          expect(Rails.logger).to have_received(:warn).with(/Failed to clear cache/)
        end
      end
    end

    context 'with areas and visits (foreign key constraint)' do
      let!(:area) { create(:area, user:) }
      let!(:visit) { create(:visit, user:, area:) }

      it 'deletes visits before areas to respect foreign key constraints' do
        user_id = user.id
        area_id = area.id
        visit_id = visit.id

        service.call

        # Both should be deleted successfully
        expect(Visit.where(id: visit_id).count).to eq(0)
        expect(Area.where(id: area_id).count).to eq(0)
        expect(User.unscoped.where(id: user_id).count).to eq(0)
      end
    end

    context 'with family associations' do
      context 'when user owns a family with other members' do
        let(:family) { create(:family, creator: user) }
        let(:other_member) { create(:user) }

        before do
          # User creates and owns a family
          create(:family_membership, user: user, family: family, role: :owner)
          # Another user is a member of that family
          create(:family_membership, user: other_member, family: family, role: :member)
        end

        it 'aborts deletion and raises error' do
          expect { service.call }.to raise_error(
            ActiveRecord::RecordInvalid,
            /Cannot delete user who owns a family with other members/
          )

          # User should NOT be deleted
          expect(User.unscoped.where(id: user.id).count).to eq(1)
          expect(user.reload.deleted?).to be true # Still soft-deleted

          # Family and memberships should still exist
          expect(Family.where(id: family.id).count).to eq(1)
          expect(Family::Membership.where(family_id: family.id).count).to eq(2)
        end

        it 'logs the validation failure' do
          allow(Rails.logger).to receive(:warn)

          expect { service.call }.to raise_error(ActiveRecord::RecordInvalid)

          expect(Rails.logger).to have_received(:warn).with(
            /Cannot delete user who owns a family with other members: user_id=#{user.id}/
          )
        end
      end

      context 'when user owns a family with no other members' do
        let(:family) { create(:family, creator: user) }

        before do
          # User creates and owns a family but is the only member
          create(:family_membership, user: user, family: family, role: :owner)
        end

        it 'deletes the user, membership, and family' do
          user_id = user.id
          family_id = family.id

          service.call

          # User should be deleted
          expect(User.unscoped.where(id: user_id).count).to eq(0)

          # All family memberships should be deleted
          expect(Family::Membership.where(family_id: family_id).count).to eq(0)

          # Family itself should be deleted
          expect(Family.where(id: family_id).count).to eq(0)
        end
      end

    end

    context 'with user as family member only' do
      it 'deletes member but preserves family and owner' do
        # Create separate users (not using the `user` from parent context)
        family_owner = create(:user)
        member_user = create(:user)
        member_user.mark_as_deleted!

        a_family = create(:family, creator: family_owner)
        create(:family_membership, user: family_owner, family: a_family, role: :owner)
        create(:family_membership, user: member_user, family: a_family, role: :member)

        member_service = described_class.new(member_user)
        member_user_id = member_user.id
        family_id = a_family.id

        member_service.call

        # Member user should be deleted
        expect(User.unscoped.where(id: member_user_id).count).to eq(0)

        # Member's membership should be deleted
        expect(Family::Membership.where(family_id: family_id, user_id: member_user_id).count).to eq(0)

        # But family should still exist (owned by family_owner)
        expect(Family.where(id: family_id).count).to eq(1)

        # And owner's membership should still exist
        expect(Family::Membership.where(family_id: family_id, user_id: family_owner.id).count).to eq(1)
      end
    end

    context 'when deletion fails' do
      before do
        allow(user.points).to receive(:delete_all).and_raise(StandardError, 'Database constraint violation')
      end

      it 'logs the error' do
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)

        expect { service.call }.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error).with(/Error during user deletion/)
      end

      it 'reports the exception' do
        expect(ExceptionReporter).to receive(:call).with(
          instance_of(StandardError),
          /User destroy service failed for user_id #{user.id}/
        )

        expect { service.call }.to raise_error(StandardError)
      end

      it 're-raises the error' do
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)

        expect { service.call }.to raise_error(StandardError, 'Database constraint violation')
      end
    end

    context 'with large datasets' do
      before do
        # Create many points to simulate a real user with lots of data
        create_list(:point, 100, user:)
      end

      it 'successfully deletes all records' do
        expect { service.call }.to change { Point.where(user_id: user.id).count }.from(100).to(0)
      end

      it 'completes deletion' do
        service.call

        expect(Point.where(user_id: user.id).count).to eq(0)
        expect(User.unscoped.find_by(id: user.id)).to be_nil
      end
    end
  end
end
