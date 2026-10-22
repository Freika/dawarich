# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family members are treated as entitled users', type: :model do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    ActiveJob::Base.queue_adapter = :test
  end

  let(:owner) do
    create(:user, plan: :family, status: :trial, active_until: 7.days.from_now, skip_auto_trial: true)
  end
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
  let(:member) do
    create(:user, plan: :lite, status: :inactive, active_until: nil, skip_auto_trial: true).tap do |user|
      create(:family_membership, user: user, family: family)
      Families::SyncMembers.new(family: family.reload).call
    end
  end

  def lapse_the_owner
    perform_enqueued_jobs(only: Families::MemberSyncJob) do
      owner.update!(status: :inactive, active_until: 1.day.ago)
    end
  end

  describe 'while the owner plan is live' do
    it 'counts the member as an active user' do
      expect(User.active_or_trial).to include(member)
    end

    it 'stops nagging the member to subscribe' do
      expect(member.reload.can_subscribe?).to be false
    end

    it 'gives the member full access' do
      expect(member.reload.full_access?).to be true
    end
  end

  describe 'once the owner plan lapses' do
    it 'drops the member out of the active user set' do
      member
      lapse_the_owner

      expect(User.active_or_trial).not_to include(member.reload)
    end

    it 'expires the member billing period' do
      member
      lapse_the_owner

      expect(member.reload.active_until).to be_past
    end

    it 'lets the member subscribe on their own again' do
      member
      lapse_the_owner

      expect(member.reload.can_subscribe?).to be true
    end

    it 'notifies the member' do
      member

      expect { lapse_the_owner }
        .to have_enqueued_job(Families::LapseNotificationJob).with(member.id, family.id)
    end
  end

  describe 'unrelated users' do
    it 'still excludes a lapsed stranger from the active set' do
      stranger = create(:user, status: :inactive, active_until: nil, skip_auto_trial: true)

      expect(User.active_or_trial).not_to include(stranger)
    end

    it 'still lets a lapsed stranger subscribe' do
      stranger = create(:user, status: :inactive, active_until: nil, skip_auto_trial: true)

      expect(stranger.can_subscribe?).to be true
    end

    it 'leaves the owner able to convert their own trial' do
      member

      expect(owner.reload.can_subscribe?).to be true
    end
  end
end
