# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::Invitations::CleanupJob, type: :job do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }

  def invitation(status:, expires_at:, updated_at: Time.current)
    create(:family_invitation, family:, invited_by: user, status:, expires_at:)
      .tap { |record| record.update_columns(updated_at:) }
  end

  it 'expires pending invitations past their expiry without touching updated_at' do
    past = invitation(status: :pending, expires_at: 1.minute.ago, updated_at: 3.days.ago)
    future = invitation(status: :pending, expires_at: 1.day.from_now)

    expect { described_class.perform_now }.not_to(change { past.reload.updated_at })

    expect(past.reload).to be_expired
    expect(future.reload).to be_pending
  end

  it 'leaves accepted invitations alone after their expiry' do
    accepted = invitation(status: :accepted, expires_at: 1.day.ago, updated_at: 40.days.ago)

    described_class.perform_now

    expect(accepted.reload).to be_accepted
  end

  it 'deletes expired and cancelled invitations last updated more than 30 days ago' do
    old_expired = invitation(status: :expired, expires_at: 40.days.ago, updated_at: 31.days.ago)
    old_cancelled = invitation(status: :cancelled, expires_at: 1.day.from_now, updated_at: 31.days.ago)
    recent_expired = invitation(status: :expired, expires_at: 10.days.ago, updated_at: 29.days.ago)

    described_class.perform_now

    expect(Family::Invitation.where(id: [old_expired.id, old_cancelled.id])).to be_empty
    expect(recent_expired.reload).to be_expired
  end

  it 'expires and deletes a stale pending invitation in the same run' do
    stale = invitation(status: :pending, expires_at: 35.days.ago, updated_at: 38.days.ago)

    described_class.perform_now

    expect(Family::Invitation.exists?(stale.id)).to be(false)
  end

  it 'changes nothing while Oban owns the cron entry' do
    job_owner!('cron:nightly_family_invitations_cleanup_job', :oban)
    pending = invitation(status: :pending, expires_at: 1.minute.ago)
    old_cancelled = invitation(status: :cancelled, expires_at: 1.day.from_now, updated_at: 31.days.ago)

    described_class.perform_now

    expect(pending.reload).to be_pending
    expect(old_cancelled.reload).to be_cancelled
  end
end
