# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::SyncMembers do
  subject(:service) { described_class.new(family: family) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    ActiveJob::Base.queue_adapter = :test
  end

  let(:owner) do
    create(:user, plan: :family, status: :trial, active_until: 7.days.from_now, skip_auto_trial: true)
  end
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }

  def add_member(**attrs)
    create(:user, { plan: :lite, status: :inactive, active_until: nil, skip_auto_trial: true }.merge(attrs))
      .tap { |user| create(:family_membership, user: user, family: family) }
  end

  describe 'while the owner plan is live' do
    let!(:member) { add_member }

    it 'puts the member on the pro plan' do
      service.call

      expect(member.reload).to be_pro
    end

    it 'marks the member active' do
      service.call

      expect(member.reload).to be_active
    end

    it 'gives the member the owner billing period' do
      service.call

      expect(member.reload.active_until).to be_within(1.second).of(owner.active_until)
    end

    it 'leaves the member without a subscription source of their own' do
      service.call

      expect(member.reload).to be_sub_source_none
    end

    it 'does not email anyone' do
      expect { service.call }.not_to have_enqueued_job(Families::LapseNotificationJob)
    end

    it 'keeps the paid period when a callback arrives without a date' do
      service.call
      paid_until = family.reload.access_until
      owner.update!(active_until: nil)

      described_class.new(family: family.reload).call

      expect(family.reload.access_until).to be_within(1.second).of(paid_until)
    end

    it 'does not lapse members over a callback without a date' do
      service.call
      owner.update!(active_until: nil)

      described_class.new(family: family.reload).call

      expect(member.reload).to be_active
    end

    it 'does not re-enqueue a sync for its own writes' do
      expect { service.call }.not_to have_enqueued_job(Families::MemberSyncJob)
    end

    it 'leaves the owner untouched' do
      expect { service.call }.not_to(change { owner.reload.attributes.slice('status', 'plan', 'active_until') })
    end
  end

  describe 'when the owner plan lapses' do
    let!(:member) { add_member(plan: :pro, status: :active, active_until: 7.days.from_now) }

    before { owner.update!(status: :inactive, active_until: 1.day.ago) }

    it 'lapses the member too' do
      service.call

      expect(member.reload).to be_inactive
    end

    it 'expires the member billing period' do
      service.call

      expect(member.reload.active_until).to be_past
    end

    it 'settles on a stable date rather than churning the row' do
      service.call
      first = member.reload.active_until

      described_class.new(family: family.reload).call

      expect(member.reload.active_until).to eq(first)
    end

    it 'drops the member back to the free tier' do
      service.call

      expect(member.reload).to be_lite
    end

    it 'notifies the member' do
      expect { service.call }
        .to have_enqueued_job(Families::LapseNotificationJob).with(member.id, family.id)
    end

    it 'stays quiet once the member has already been notified' do
      Families::LapseNotice.mark(member)

      expect { described_class.new(family: family.reload).call }
        .not_to have_enqueued_job(Families::LapseNotificationJob)
    end

    it 'notifies again after access is restored and lapses a second time' do
      Families::LapseNotice.mark(member)
      owner.update!(status: :active, active_until: 30.days.from_now)
      described_class.new(family: family.reload).call
      owner.update!(status: :inactive, active_until: 1.day.ago)

      expect { described_class.new(family: family.reload).call }
        .to have_enqueued_job(Families::LapseNotificationJob)
    end

    it 'sends nothing when the caller asks for a silent sync' do
      expect { described_class.new(family: family, notify: false).call }
        .not_to have_enqueued_job(Families::LapseNotificationJob)
    end

    it 'still marks a silent sync notified so it is not emailed later' do
      described_class.new(family: family, notify: false).call

      expect { described_class.new(family: family.reload).call }
        .not_to have_enqueued_job(Families::LapseNotificationJob)
    end
  end

  describe 'a member who pays for their own subscription' do
    let!(:member) do
      add_member(plan: :pro, status: :active, active_until: 1.year.from_now, subscription_source: :paddle)
    end

    it 'is never overwritten while the family is live' do
      expect { service.call }
        .not_to(change { member.reload.attributes.slice('status', 'plan', 'active_until') })
    end

    it 'is not lapsed when the family lapses' do
      owner.update!(status: :inactive, active_until: 1.day.ago)

      service.call

      expect(member.reload).to be_active
    end
  end

  describe 'when the owner leaves the family plan entirely' do
    let!(:member) { add_member(plan: :pro, status: :active, active_until: 7.days.from_now) }

    it 'lapses the member' do
      owner.update!(plan: :pro)

      service.call

      expect(member.reload).to be_inactive
    end
  end

  describe 'a member whose own subscription lapses' do
    let!(:member) do
      add_member(plan: :pro, status: :active, active_until: 1.year.from_now, subscription_source: :paddle)
    end

    it 'is brought back onto the family plan once their own subscription lapses' do
      member.update!(status: :inactive, active_until: 1.day.ago)

      described_class.new(family: family.reload).call

      expect(member.reload).to be_active
      expect(member.reload.active_until).to be_within(1.second).of(family.reload.access_until)
    end

    it 'is marked as having no subscription of their own once mirrored' do
      member.update!(status: :inactive, active_until: 1.day.ago)

      described_class.new(family: family.reload).call

      expect(member.reload).to be_sub_source_none
    end

    it 'triggers a sync from their own subscription change' do
      expect { member.update!(status: :inactive, active_until: 1.day.ago) }
        .to have_enqueued_job(Families::MemberSyncJob).with(family.id)
    end
  end

  describe 'on self-hosted instances' do
    let!(:member) { add_member }

    it 'changes nothing' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

      expect { service.call }
        .not_to(change { member.reload.attributes.slice('status', 'plan', 'active_until') })
    end
  end

  describe 'the marker that identifies an inherited grant' do
    let!(:member) { add_member(subscription_source: :paddle, active_until: 1.day.ago) }

    it 'stamps a granted member as having no subscription of their own' do
      service.call

      expect(member.reload).to be_sub_source_none
    end
  end
end
