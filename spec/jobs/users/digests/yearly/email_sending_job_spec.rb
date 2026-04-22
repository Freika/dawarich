# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Yearly::EmailSendingJob, type: :job do
  let(:user) { create(:user, settings: { 'yearly_digest_emails_enabled' => true }) }
  let(:year) { 2024 }
  let!(:digest) { create(:users_digest, user: user, year: year, period_type: :yearly) }

  it 'enqueues to the mailers queue' do
    expect(described_class.new.queue_name).to eq('mailers')
  end

  it 'sends the email and marks sent_at when all conditions are met' do
    expect {
      described_class.new.perform(user.id, year)
    }.to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)
    expect(digest.reload.sent_at).to be_present
  end

  it 'skips when the toggle is off' do
    user.update!(settings: user.settings.merge('yearly_digest_emails_enabled' => false))

    expect {
      described_class.new.perform(user.id, year)
    }.not_to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)
  end

  it 'skips when sent_at is already present (idempotent)' do
    digest.update!(sent_at: 1.day.ago)

    expect {
      described_class.new.perform(user.id, year)
    }.not_to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)
  end

  it 'skips when the digest record is missing' do
    digest.destroy!

    expect {
      described_class.new.perform(user.id, year)
    }.not_to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)
  end

  it 'skips when distance is zero' do
    digest.update!(distance: 0)

    expect {
      described_class.new.perform(user.id, year)
    }.not_to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)
  end

  it 'does not raise when the user does not exist' do
    expect { described_class.new.perform(999_999, year) }.not_to raise_error
  end

  it 'does not send when the user is soft-deleted' do
    user.mark_as_deleted!

    expect {
      described_class.new.perform(user.id, year)
    }.not_to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)
  end
end
