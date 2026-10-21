# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::LapseNotificationJob, type: :job do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }
  let(:member) { create(:user, skip_auto_trial: true) }

  def stub_mailer(deliver: true)
    mailer = double('mailer')
    allow(FamilyMailer).to receive(:plan_lapsed).with(member, family).and_return(mailer)
    if deliver
      allow(mailer).to receive(:deliver_now)
    else
      allow(mailer).to receive(:deliver_now).and_raise(Net::SMTPServerBusy, 'mailbox unavailable')
    end
    mailer
  end

  it 'delivers the lapse email' do
    mailer = stub_mailer

    described_class.perform_now(member.id, family.id)

    expect(mailer).to have_received(:deliver_now)
  end

  it 'records that the member was notified' do
    stub_mailer

    described_class.perform_now(member.id, family.id)

    expect(Families::LapseNotice.notified?(member.reload)).to be true
  end

  it 'leaves the member unnotified when delivery fails so a retry can send' do
    stub_mailer(deliver: false)

    expect { described_class.perform_now(member.id, family.id) }.to raise_error(Net::SMTPServerBusy)
    expect(Families::LapseNotice.notified?(member.reload)).to be false
  end

  it 'does not send twice for the same lapse' do
    mailer = stub_mailer
    described_class.perform_now(member.id, family.id)

    described_class.perform_now(member.id, family.id)

    expect(mailer).to have_received(:deliver_now).once
  end

  it 'owned by oban forwards with lapse_at' do
    access_until = Time.utc(2026, 9, 30, 12)
    family.update_columns(access_until:)
    member
    JobOutbox.delete_all
    job_owner!('command:mail.family_lapse', :oban)
    mailer = stub_mailer
    job = described_class.new(member.id, family.id)

    job.perform_now

    expect(mailer).not_to have_received(:deliver_now)
    expect(Families::LapseNotice.notified?(member.reload)).to be false
    expect(JobOutbox.find(job.job_id)).to have_attributes(
      command_type: 'mail.family_lapse', aggregate_id: member.id,
      dedupe_key: "family-lapse:#{family.id}:#{member.id}:2026-09-30T12:00:00Z",
      payload: { 'user_id' => member.id, 'family_id' => family.id, 'locale' => 'en',
                 'lapse_at' => '2026-09-30T12:00:00Z' }
    )
  end

  it 'ignores a member that no longer exists' do
    expect { described_class.perform_now(-1, family.id) }.not_to raise_error
  end
end
