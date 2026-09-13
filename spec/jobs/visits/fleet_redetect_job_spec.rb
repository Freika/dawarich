# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::FleetRedetectJob do
  it 'fans out one per-user job for every active user with points' do
    with_points = create(:user)
    without_points = create(:user)
    User.where(id: with_points.id).update_all(points_count: 42)
    User.where(id: without_points.id).update_all(points_count: 0)

    expect { described_class.perform_now }
      .to have_enqueued_job(Visits::UserRedetectJob).with(with_points.id).exactly(:once)

    enqueued_ids = enqueued_jobs.select { |j| j['job_class'] == 'Visits::UserRedetectJob' }
                                .map { |j| j['arguments'].first }
    expect(enqueued_ids).not_to include(without_points.id)
  end

  it 'staggers the per-user jobs so the fleet does not land at once' do
    users = create_list(:user, 3)
    User.where(id: users.map(&:id)).update_all(points_count: 10)

    described_class.perform_now

    target_ids = users.map(&:id)
    schedule = enqueued_jobs.select { |j| j['job_class'] == 'Visits::UserRedetectJob' }
                            .select { |j| target_ids.include?(j['arguments'].first) }
                            .map { |j| j['scheduled_at'] }
    expect(schedule.size).to eq(3)
    expect(schedule).to all(be_present)
    expect(schedule.map { |at| Time.zone.parse(at.to_s).to_i }.uniq.size).to eq(3)
  end

  it 'runs on the low_priority queue' do
    expect(described_class.new.queue_name).to eq('low_priority')
    expect(Visits::UserRedetectJob.new.queue_name).to eq('low_priority')
  end
end
