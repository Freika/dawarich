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

  it 'uses Users::Destroy.new(user).call' do
    user = create(:user, status: :pending_payment, signup_variant: 'reverse_trial',
                         created_at: 31.days.ago, skip_auto_trial: true)

    destroy_service = instance_double(Users::Destroy, call: true)
    expect(Users::Destroy).to receive(:new).with(an_instance_of(User)).and_return(destroy_service)

    described_class.new.perform
  end
end
