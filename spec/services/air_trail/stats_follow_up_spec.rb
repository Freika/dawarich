# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::StatsFollowUp do
  let(:user) { create(:user, settings: { 'timezone' => 'America/New_York' }) }

  before { create(:flight, user:, external_id: 1, flight_date: Date.new(2026, 4, 20)) }

  def payload(months: [[2026, 3]], epochs: [Time.utc(2026, 2, 1, 3).to_i])
    { 'user_id' => user.id, 'months' => months, 'departure_epochs' => epochs }
  end

  it 'enqueues one stats job per month from before and after the sync' do
    expect { described_class.call(payload) }
      .to have_enqueued_job(Stats::CalculatingJob).exactly(3).times
    [[2026, 3], [2026, 1], [2026, 4]].each do |year, month|
      expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, year, month).once
    end
  end

  it 'reads departures of undated flights in the user zone' do
    described_class.call(payload(months: [], epochs: [Time.utc(2026, 2, 1, 3).to_i]))

    expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2026, 1)
    expect(Stats::CalculatingJob).not_to have_been_enqueued.with(user.id, 2026, 2)
  end

  it 'does nothing for a deleted user' do
    expect { described_class.call(payload.merge('user_id' => -1)) }.not_to have_enqueued_job
  end

  it 'is dispatched by the reverse-outbox poller' do
    phoenix_tables!
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(
                                            ['INSERT INTO phoenix.rails_commands (kind, payload) ' \
                                             "VALUES ('airtrail_stats', ?::jsonb)",
                                             payload.to_json]
                                          ))

    expect(RailsCommands::Poller.drain_once).to eq(1)
    expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2026, 4)
    expect(RailsCommands::Poller.drain_once).to eq(0)
  end
end
