# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::RetentionCandidatesQuery do
  # The factory's after_commit activation rewrites status, so state is set
  # with update_columns after creation.
  def user_with(status:, active_until:, created_at: 2.years.ago, admin: false)
    create(:user).tap do |user|
      user.update_columns(status: User.statuses[status], active_until:, created_at:, admin:)
    end
  end

  def candidates(today)
    described_class.new(today:).call.to_a
  end

  def row_for(user, today)
    candidates(today).find { |row| row.id == user.id }
  end

  let(:launch_warning_day) { Date.new(2026, 12, 2) }

  it 'floors the deletion date of a long-lapsed account at launch' do
    user = user_with(status: :inactive, active_until: Time.zone.local(2025, 6, 1))

    expect(row_for(user, launch_warning_day).computed_deletion_on).to eq(Date.new(2027, 1, 1))
  end

  it 'anchors on signup when the account never had a subscription' do
    user = user_with(status: :pending_payment, active_until: nil, created_at: Time.zone.local(2025, 9, 1))

    expect(row_for(user, launch_warning_day).computed_deletion_on).to eq(Date.new(2027, 1, 1))
  end

  it 'includes a trial whose access has ended' do
    user = user_with(status: :trial, active_until: Time.zone.local(2025, 6, 1))

    expect(row_for(user, launch_warning_day)).to be_present
  end

  it 'deletes 12 months after access ended once that is past launch' do
    user = user_with(status: :inactive, active_until: Time.zone.local(2026, 3, 15, 12))

    expect(row_for(user, Date.new(2027, 3, 1)).computed_deletion_on).to eq(Date.new(2027, 3, 15))
  end

  it 'leaves out accounts more than 30 days before their deletion date' do
    user = user_with(status: :inactive, active_until: Time.zone.local(2025, 6, 1))

    expect(row_for(user, Date.new(2026, 12, 1))).to be_nil
  end

  it 'includes accounts whose deletion date has passed' do
    user = user_with(status: :inactive, active_until: Time.zone.local(2025, 6, 1))

    expect(row_for(user, Date.new(2027, 2, 1))).to be_present
  end

  it 'never includes an active user, even with a past active_until' do
    user = user_with(status: :active, active_until: Time.zone.local(2025, 6, 1))

    expect(row_for(user, launch_warning_day)).to be_nil
  end

  it 'never includes a trial that is still running' do
    user = user_with(status: :trial, active_until: 3.days.from_now, created_at: Time.zone.local(2025, 1, 1))

    expect(row_for(user, launch_warning_day)).to be_nil
  end

  it 'never includes an admin' do
    user = user_with(status: :inactive, active_until: Time.zone.local(2025, 6, 1), admin: true)

    expect(row_for(user, launch_warning_day)).to be_nil
  end

  it 'never includes a soft-deleted user' do
    user = user_with(status: :inactive, active_until: Time.zone.local(2025, 6, 1))
    user.mark_as_deleted!

    expect(row_for(user, launch_warning_day)).to be_nil
  end
end
