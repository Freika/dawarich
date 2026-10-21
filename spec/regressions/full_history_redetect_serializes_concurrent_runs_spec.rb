# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visits::FullHistoryRedetectJob serializes concurrent runs' do
  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }
  let(:lease_name) { "tracks:per_user_lock:#{user.id}" }

  def lease_count
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM phoenix.leases WHERE name = #{ActiveRecord::Base.connection.quote(lease_name)}"
    ).to_i
  end

  before do
    # New accounts are born re-detected (DB default), which starts the cooldown.
    user.update!(visits_redetected_at: 2.hours.ago)
    phoenix_leases!
    3.times do |i|
      create(:point, user: user,
                     latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
    end
  end

  it 'a second worker blocked by the per-user lock does not destroy suggested visits and notifies the user' do
    suggested = create(:visit, user: user, status: :suggested,
                                started_at: Time.zone.at(base_ts),
                                ended_at: Time.zone.at(base_ts + 600),
                                duration: 600, name: 'old')

    stub_const('Tracks::PerUserLock::DEFAULT_ACQUIRE_TIMEOUT', 0.2)
    ActiveRecord::Base.connection.execute(
      'INSERT INTO phoenix.leases (name, holder, expires_at) ' \
      "VALUES (#{ActiveRecord::Base.connection.quote(lease_name)}, 'other-holder', " \
      "statement_timestamp() + interval '60 seconds')"
    )

    expect { Visits::FullHistoryRedetectJob.new.perform(user.id) }.not_to raise_error

    expect(Visit.where(id: suggested.id)).to exist
    busy_notice = user.notifications.where(kind: :warning, title: 'Visit re-detection busy')
    expect(busy_notice).to exist
  end

  it 'acquires the per-user lock during a successful run and releases it afterwards' do
    observed_during_perform = nil
    allow_any_instance_of(Visits::SmartDetect).to receive(:call) do
      observed_during_perform = lease_count
      []
    end

    Visits::FullHistoryRedetectJob.new.perform(user.id)

    expect(observed_during_perform).to eq(1)
    expect(lease_count).to eq(0)
  end
end
