# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::AcceptInvitation do
  let(:family) { create(:family) }
  let(:invitee) { create(:user, email: 'invitee@example.com') }
  let(:invitation) { create(:family_invitation, family: family, email: invitee.email) }
  let(:service) { described_class.new(invitation: invitation, user: invitee) }

  describe '#call' do
    context 'when invitation can be accepted' do
      it 'creates membership for user' do
        expect { service.call }.to change(Family::Membership, :count).by(1)
        membership = invitee.reload.family_membership
        expect(membership.family).to eq(family)
        expect(membership.role).to eq('member')
      end

      it 'updates invitation status to accepted' do
        service.call
        invitation.reload
        expect(invitation.status).to eq('accepted')
      end

      it 'notifies the family owner, who did not see it happen' do
        expect { service.call }.to change(Notification, :count).by(1)

        owner_notification = Notification.find_by(user: family.creator, title: 'New Family Member!')
        expect(owner_notification).to be_present
        expect(owner_notification.action_path).to eq('/family')
      end

      it 'does not notify the invitee, who is already told by the page' do
        service.call

        expect(invitee.notifications).to be_empty
      end

      it 'localizes the owner notification for the owner' do
        invitee.update!(settings: { 'locale' => 'en' })
        family.creator.update!(settings: { 'locale' => 'fr' })

        I18n.with_locale(:en) { service.call }

        expect(family.creator.notifications.last.title).to eq('Nouveau membre de la famille !')
      end

      context 'when the caller shows no confirmation of its own' do
        let(:service) { described_class.new(invitation: invitation, user: invitee, welcome_notification: true) }

        it 'welcomes the invitee in their own language' do
          invitee.update!(settings: { 'locale' => 'fr' })

          I18n.with_locale(:en) { service.call }

          welcome = invitee.notifications.last
          expect(welcome.title).to eq('Bienvenue dans la famille !')
          expect(welcome.action_path).to eq('/family')
        end

        it 'still notifies the owner' do
          expect { service.call }.to change(Notification, :count).by(2)
        end
      end

      it 'returns true' do
        expect(service.call).to be true
      end
    end

    context 'when the family owner no longer holds the plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        family.creator.update!(plan: :pro)
      end

      it 'refuses the invitation' do
        expect(service.call).to be false
        expect(service.error_message).to eq("This family's plan is no longer active.")
        expect(invitee.reload.family_membership).to be_nil
      end
    end

    context 'effective access lifecycle (cloud, family-plan owner)' do
      let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
      let(:family) { create(:family, creator: owner) }
      let(:invitee) { create(:user, plan: :lite, email: 'invitee@example.com', skip_auto_trial: true) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        create(:family_membership, :owner, family: family, user: owner)
      end

      it 'grants full access immediately upon joining' do
        expect(invitee.full_access?).to be false

        service.call
        invitee.reload

        expect(invitee.full_access?).to be true
        expect(invitee.plan_restricted?).to be false
      end

      it 'puts the joining member on the owner plan and billing period' do
        service.call
        invitee.reload

        expect(invitee.plan).to eq('pro')
        expect(invitee).to be_active
        expect(invitee.active_until).to be_within(1.second).of(owner.active_until)
      end
    end

    context 'when user is already in another family' do
      let(:other_family) { create(:family) }
      let!(:existing_membership) { create(:family_membership, user: invitee, family: other_family) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end

      it 'sets appropriate error message' do
        service.call
        expect(service.error_message).to eq('You must leave your current family before joining a new one.')
      end

      it 'does not change user family' do
        expect { service.call }.not_to(change { invitee.reload.family })
      end
    end

    context 'when invitation is expired' do
      let(:invitation) { create(:family_invitation, family: family, email: invitee.email, expires_at: 1.day.ago) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end
    end

    context 'when invitation is not pending' do
      let(:invitation) { create(:family_invitation, :accepted, family: family, email: invitee.email) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end
    end

    context 'when email does not match user' do
      let(:wrong_user) { create(:user, email: 'wrong@example.com') }
      let(:service) { described_class.new(invitation: invitation, user: wrong_user) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end
    end

    context 'when the invitation fills the last seat (cloud)' do
      let(:owner) { create(:user, plan: :family, active_until: 1.month.from_now, skip_auto_trial: true) }
      let(:family) { create(:family, creator: owner) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        create(:family_membership, :owner, family: family, user: owner)
        create_list(:family_membership, Family::MAX_MEMBERS - 2, family: family, role: :member)
        invitation
      end

      it 'accepts the invitation that fills the last seat' do
        expect(service.call).to be(true), service.error_message
        expect(family.members.count).to eq(Family::MAX_MEMBERS)
      end
    end

    context 'when family is at max capacity' do
      let(:owner) { create(:user, plan: :family, active_until: 1.month.from_now, skip_auto_trial: true) }
      let(:family) { create(:family, creator: owner) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        create(:family_membership, :owner, family: family, user: owner)
        create_list(:family_membership, Family::MAX_MEMBERS - 1, family: family, role: :member)
      end

      it 'returns false with the capacity message' do
        expect(service.call).to be false
        expect(service.error_message).to eq(
          I18n.t('services.families.accept_invitation.this_family_has_reached_the_maximum_number_of_members')
        )
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end
    end
  end

  describe '#error_code' do
    it 'is nil after a successful call' do
      service.call
      expect(service.error_code).to be_nil
    end

    it 'is invitation_invalid for an expired invitation' do
      invitation.update!(expires_at: 1.day.ago)
      service.call
      expect(service.error_code).to eq(:invitation_invalid)
    end

    it 'is email_mismatch for another user' do
      service = described_class.new(invitation: invitation, user: create(:user))
      service.call
      expect(service.error_code).to eq(:email_mismatch)
    end

    it 'is already_in_family for a member of another family' do
      create(:family_membership, user: invitee, family: create(:family))
      service.call
      expect(service.error_code).to eq(:already_in_family)
    end

    it 'is invitation_invalid when the family owner account is gone' do
      invitation
      family.creator.mark_as_deleted!
      service = described_class.new(invitation: Family::Invitation.find(invitation.id), user: invitee)

      expect(ExceptionReporter).not_to receive(:call)
      expect(service.call).to be false
      expect(service.error_code).to eq(:invitation_invalid)
    end

    it 'is already_in_family for a user who joined a family after being loaded' do
      stale_invitee = User.find(invitee.id).tap(&:family_membership)
      create(:family_membership, user: invitee, family: create(:family))
      service = described_class.new(invitation: invitation, user: stale_invitee)

      expect { expect(service.call).to be false }.not_to change(Family::Membership, :count)
      expect(service.error_code).to eq(:already_in_family)
    end

    it 'is already_in_family when another accept by the same user wins the race' do
      allow(Family::Membership).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      expect(ExceptionReporter).not_to receive(:call)
      expect(service.call).to be false
      expect(service.error_code).to eq(:already_in_family)
    end

    it 'is plan_inactive when the owner no longer holds the plan' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      family.creator.update!(plan: :pro)
      service.call
      expect(service.error_code).to eq(:plan_inactive)
    end

    it 'is family_full when every cloud seat is taken' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      family.creator.update!(plan: :family, active_until: 1.month.from_now)
      create(:family_membership, :owner, family: family, user: family.creator)
      create_list(:family_membership, Family::MAX_MEMBERS - 1, family: family, role: :member)
      service.call
      expect(service.error_code).to eq(:family_full)
    end

    [ActiveRecord::RecordInvalid.new, StandardError.new('boom')].each do |error|
      it "is unexpected_error when #{error.class} is raised" do
        allow(Family::Membership).to receive(:create!).and_raise(error)
        allow(ExceptionReporter).to receive(:call)
        expect(service.call).to be false
        expect(service.error_code).to eq(:unexpected_error)
      end
    end
  end
end
