# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Monthly::EmailSendingJob, type: :job do
  let(:user) { create(:user, settings: { 'monthly_digest_emails_enabled' => true }) }
  let!(:digest) do
    user.digests.create!(year: 2026, month: 3, period_type: :monthly, distance: 312)
  end

  it 'sends the email and marks sent_at when all conditions are met' do
    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.to have_enqueued_mail(Users::DigestsMailer, :monthly_digest)
    expect(digest.reload.sent_at).to be_present
  end

  it 'skips when the toggle is off' do
    user.update!(settings: user.settings.merge('monthly_digest_emails_enabled' => false))

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.not_to have_enqueued_mail(Users::DigestsMailer, :monthly_digest)
  end

  it 'skips when sent_at is already present (idempotent)' do
    digest.update!(sent_at: 1.day.ago)

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.not_to have_enqueued_mail(Users::DigestsMailer, :monthly_digest)
  end

  it 'skips when the digest record is missing' do
    digest.destroy!

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.not_to have_enqueued_mail(Users::DigestsMailer, :monthly_digest)
  end

  it 'skips when distance is zero' do
    digest.update!(distance: 0)

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.not_to have_enqueued_mail(Users::DigestsMailer, :monthly_digest)
  end
end
