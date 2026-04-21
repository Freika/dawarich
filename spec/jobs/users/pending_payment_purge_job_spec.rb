# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::PendingPaymentPurgeJob do
  it 'destroys pending_payment + reverse_trial users older than 30 days' do
    old_user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                             created_at: 31.days.ago, skip_auto_trial: true)
    recent_user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                                created_at: 10.days.ago, skip_auto_trial: true)

    described_class.new.perform

    expect(User.where(id: old_user.id)).to be_empty
    expect(User.where(id: recent_user.id)).to exist
  end

  it 'leaves non-pending_payment users alone' do
    active_user = create(:user, status: :active, created_at: 31.days.ago)
    other_variant = create(:user, status: :pending_payment, signup_variant: 'default',
                                  created_at: 31.days.ago, skip_auto_trial: true)

    described_class.new.perform

    expect(User.where(id: active_user.id)).to exist
    expect(User.where(id: other_variant.id)).to exist
  end

  it 'skips users whose state changed after being selected (webhook race)' do
    # User qualifies at SELECT time but a webhook flips them to :active before the DELETE.
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 31.days.ago, skip_auto_trial: true)

    # Simulate the race: after the .find_each picks them up, another transaction updates
    # the user. We verify the job re-checks within the lock.
    allow_any_instance_of(User).to receive(:with_lock).and_wrap_original do |meth, *args, &block|
      # Before the lock body runs, simulate a webhook updating the user.
      User.where(id: meth.receiver.id).update_all(status: User.statuses[:active],
                                                  subscription_source: User.subscription_sources[:paddle])
      meth.call(*args, &block)
    end

    described_class.new.perform

    expect(User.where(id: user.id)).to exist
    expect(user.reload.status).to eq('active')
  end
end
