# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::PendingPaymentReminderJob do
  before { ActiveJob::Base.queue_adapter = :test }

  it 'sends day-1 reminder to users created 1 day ago' do
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 25.hours.ago, skip_auto_trial: true)
    described_class.new.perform
    expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'pending_payment_day_1')
  end

  it 'sends day-3 reminder to users created 3 days ago' do
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 3.days.ago - 1.hour, skip_auto_trial: true)
    described_class.new.perform
    expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'pending_payment_day_3')
  end

  it 'sends day-7 reminder to users created 7 days ago' do
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 7.days.ago - 1.hour, skip_auto_trial: true)
    described_class.new.perform
    expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'pending_payment_day_7')
  end

  it 'sends BOTH day-1 and day-3 for a 4-day-old user whose day-3 cron was missed' do
    # age = 4d, no reminders recorded -> should enqueue day_1 and day_3 (catch-up)
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 4.days.ago, skip_auto_trial: true)
    described_class.new.perform

    expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'pending_payment_day_1')
    expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'pending_payment_day_3')
  end

  it 'skips users who have completed payment' do
    create(:user, status: :active, created_at: 25.hours.ago)
    described_class.new.perform
    expect(Users::MailerSendingJob).not_to have_been_enqueued
  end

  it 'dedupes via pending_payment_reminders hash in settings' do
    create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                  created_at: 25.hours.ago, skip_auto_trial: true,
                  settings: { 'pending_payment_reminders' => { '1' => true } })
    described_class.new.perform
    expect(Users::MailerSendingJob).not_to have_been_enqueued
  end

  it 'handles legacy array-shaped reminder settings (backward compat with old day_X keys)' do
    # Old data format: { 'pending_payment_reminders' => ['day_1'] }
    create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                  created_at: 25.hours.ago, skip_auto_trial: true,
                  settings: { 'pending_payment_reminders' => ['day_1'] })
    described_class.new.perform

    expect(Users::MailerSendingJob).not_to have_been_enqueued.with(anything, 'pending_payment_day_1')
  end

  it 'only sends day-3 catch-up when day-1 is already recorded' do
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 4.days.ago, skip_auto_trial: true,
                         settings: { 'pending_payment_reminders' => { '1' => true } })
    described_class.new.perform

    expect(Users::MailerSendingJob).not_to have_been_enqueued.with(user.id, 'pending_payment_day_1')
    expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'pending_payment_day_3')
  end

  it 'persists the sent flag in settings after enqueueing' do
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 25.hours.ago, skip_auto_trial: true)
    described_class.new.perform

    expect(user.reload.settings.dig('pending_payment_reminders', '1')).to eq(true)
  end
end
