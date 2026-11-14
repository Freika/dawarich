# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Memberships::Destroy do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let(:service) { described_class.new(user: user) }

  describe '#call' do
    context 'when user is a member (not owner)' do
      let(:member) { create(:user) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(user: member) }

      it 'removes the membership' do
        result = service.call
        expect(result).to be_truthy, "Expected service to succeed but got error: #{service.error_message}"
        expect(Family::Membership.count).to eq(1) # Only owner should remain
        expect(member.reload.family_membership).to be_nil
      end

      # Every other writer to a family (invite, accept, revoke, delete) locks
      # the family row first; without it a removal can deadlock with an accept.
      it 'takes the family lock before removing the membership' do
        queries = []
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          queries << payload[:sql]
        end

        service.call

        lock_at = queries.index { |sql| sql.match?(/FROM "families".*FOR UPDATE/m) }
        delete_at = queries.index { |sql| sql.match?(/DELETE FROM "family_memberships"/) }
        expect(lock_at).not_to be_nil
        expect(lock_at).to be < delete_at
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      it 'does not notify the member who left, who is already told by the page' do
        expect { service.call }.to change(Notification, :count).by(1)

        expect(member.notifications).to be_empty
      end

      it 'sends notification to family owner' do
        service.call

        owner_notification = user.notifications.last
        expect(owner_notification.title).to eq('Family Member Left')
        expect(owner_notification.content).to include(member.email)
        expect(owner_notification.content).to include(family.name)
        expect(owner_notification.action_path).to eq('/family')
      end

      it 'localizes the owner notification for the owner' do
        member.update!(settings: { 'locale' => 'fr' })
        user.update!(settings: { 'locale' => 'en' })

        I18n.with_locale(:fr) { service.call }

        expect(user.notifications.last.title).to eq('Family Member Left')
      end

      it 'returns true' do
        expect(service.call).to be true
      end
    end

    context 'when the owner removes a member' do
      let(:member) { create(:user) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(user: user, member_to_remove: member) }

      it 'tells the removed member, who has no family page to open any more' do
        expect { service.call }.to change(Notification, :count).by(1)

        notification = member.notifications.last
        expect(notification.title).to eq('Removed from Family')
        expect(notification.action_path).to be_nil
      end

      it 'does not notify the owner, who is already told by the page' do
        service.call

        expect(user.notifications).to be_empty
      end
    end

    context 'effective access lifecycle (cloud, family-plan owner)' do
      let(:user) { create(:user, plan: :family, skip_auto_trial: true) }
      let(:family) { create(:family, creator: user) }
      let(:member) { create(:user, plan: :lite, skip_auto_trial: true) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(user: user, member_to_remove: member) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'revokes full access when the member is removed, without deleting their data' do
        recent_point = create(:point, user: member, timestamp: 1.month.ago.to_i)
        old_point = create(:point, user: member, timestamp: 2.years.ago.to_i)

        expect(member.full_access?).to be true

        service.call
        member.reload

        expect(member.full_access?).to be false
        expect(member.plan_restricted?).to be true
        expect(member.points).to include(recent_point, old_point)
        expect(member.scoped_points).to include(recent_point)
        expect(member.scoped_points).not_to include(old_point)
      end
    end

    context 'when user is family owner with no other members' do
      let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

      it 'prevents owner from leaving' do
        expect { service.call }.not_to change(Family::Membership, :count)
        expect(user.reload.family_membership).to be_present
      end

      it 'does not delete the family' do
        expect { service.call }.not_to change(Family, :count)
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'sets error message' do
        service.call
        expect(service.error_message).to include('cannot remove their own membership')
      end
    end

    context 'when user is family owner with other members' do
      let(:member) { create(:user) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not remove membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
        expect(user.reload.family_membership).to be_present
      end
    end

    context 'when user is not in a family' do
      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create any notifications' do
        expect { service.call }.not_to change(Notification, :count)
      end
    end
  end

  describe '#error_code' do
    let(:member) { create(:user) }

    before do
      create(:family_membership, user: user, family: family, role: :owner)
      create(:family_membership, user: member, family: family, role: :member)
    end

    it 'is nil after a successful call' do
      service = described_class.new(user: member)
      service.call
      expect(service.error_code).to be_nil
    end

    it 'is not_in_family for a user without a family' do
      service = described_class.new(user: create(:user))
      service.call
      expect(service.error_code).to eq(:not_in_family)
    end

    it 'is owner_cannot_leave when the owner leaves' do
      service.call
      expect(service.error_code).to eq(:owner_cannot_leave)
    end

    it 'is owner_required when a member removes someone else' do
      other = create(:user)
      create(:family_membership, user: other, family: family, role: :member)
      service = described_class.new(user: member, member_to_remove: other)
      service.call
      expect(service.error_code).to eq(:owner_required)
    end

    it 'is member_not_found for a member of another family' do
      outsider = create(:user)
      create(:family_membership, user: outsider, family: create(:family), role: :member)
      service = described_class.new(user: user, member_to_remove: outsider)
      service.call
      expect(service.error_code).to eq(:member_not_found)
    end

    context 'when the membership is gone by the time the family lock is taken' do
      let(:stale_member) do
        User.find(member.id).tap do |loaded|
          loaded.family_membership
          loaded.family
        end
      end

      before do
        stale_member
        Family::Membership.where(user_id: member.id).delete_all
      end

      it 'refuses a removal with member_not_found and sends nothing' do
        service = described_class.new(user: user, member_to_remove: stale_member)

        expect(ExceptionReporter).not_to receive(:call)
        expect { expect(service.call).to be false }.not_to change(Notification, :count)
        expect(service.error_code).to eq(:member_not_found)
      end

      it 'refuses leaving with not_in_family and sends nothing' do
        service = described_class.new(user: stale_member)

        expect(ExceptionReporter).not_to receive(:call)
        expect { expect(service.call).to be false }.not_to change(Notification, :count)
        expect(service.error_code).to eq(:not_in_family)
      end
    end

    it 'is cannot_remove_owner when the target is an owner' do
      co_owner = create(:user)
      create(:family_membership, user: co_owner, family: family, role: :owner)
      service = described_class.new(user: user, member_to_remove: co_owner)
      service.call
      expect(service.error_code).to eq(:cannot_remove_owner)
    end

    [ActiveRecord::RecordInvalid.new, StandardError.new('boom')].each do |error|
      it "is unexpected_error when #{error.class} is raised" do
        allow_any_instance_of(Family::Membership).to receive(:destroy!).and_raise(error)
        allow(ExceptionReporter).to receive(:call)
        service = described_class.new(user: member)
        expect(service.call).to be false
        expect(service.error_code).to eq(:unexpected_error)
      end
    end
  end
end
