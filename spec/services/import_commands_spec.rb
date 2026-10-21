# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportCommands do
  let!(:user) { create(:user) }
  let!(:import) { create(:import, user:) }

  it 'routes update_points_count to Sidekiq while Sidekiq owns it' do
    expect { described_class.update_points_count(import.id, producer: 'spec') }
      .to have_enqueued_job(Import::UpdatePointsCountJob).with(import.id)
    expect(JobOutbox.count).to eq(0)
  end

  it 'writes one update_points_count outbox row carrying only the import id while Oban owns it' do
    job_owner!(ImportCommands::UPDATE_POINTS_COUNT_KEY, :oban)

    expect { described_class.update_points_count(import.id, producer: 'spec') }.not_to have_enqueued_job
    row = JobOutbox.pending.sole
    expect(row).to have_attributes(command_type: 'imports.update_points_count', command_version: 1,
                                   payload: { 'import_id' => import.id }, aggregate_id: import.id,
                                   dedupe_key: "points-count:#{import.id}")
  end

  it 'writes one airtrail_flights outbox row carrying only the user id while Oban owns it' do
    job_owner!(ImportCommands::AIRTRAIL_FLIGHTS_KEY, :oban)

    described_class.airtrail_flights(user.id, producer: 'spec')
    row = JobOutbox.pending.sole
    expect(row).to have_attributes(command_type: 'imports.airtrail_flights', command_version: 1,
                                   payload: { 'user_id' => user.id }, aggregate_id: user.id,
                                   dedupe_key: "airtrail:#{user.id}")
  end

  it 'collapses a second pending airtrail command for the same user but not for another user' do
    job_owner!(ImportCommands::AIRTRAIL_FLIGHTS_KEY, :oban)
    other = create(:user)

    2.times { described_class.airtrail_flights(user.id, producer: 'spec') }
    described_class.airtrail_flights(other.id, producer: 'spec')

    expect(JobOutbox.pending.pluck(:aggregate_id)).to contain_exactly(user.id, other.id)
  end

  it 'enqueues the legacy airtrail job only when the producing transaction commits' do
    ActiveRecord::Base.transaction do
      described_class.airtrail_flights(user.id, producer: 'spec')
      raise ActiveRecord::Rollback
    end

    expect(AirTrail::ImportFlightsJob).not_to have_been_enqueued
  end

  it 'enqueues the legacy points-count job only when the producing transaction commits' do
    ActiveRecord::Base.transaction do
      described_class.update_points_count(import.id, producer: 'spec')
      raise ActiveRecord::Rollback
    end

    expect(Import::UpdatePointsCountJob).not_to have_been_enqueued
  end

  it 'rehomes pending commands of both types to their legacy jobs' do
    job_owner!(ImportCommands::UPDATE_POINTS_COUNT_KEY, :oban)
    job_owner!(ImportCommands::AIRTRAIL_FLIGHTS_KEY, :oban)
    described_class.update_points_count(import.id, producer: 'spec')
    described_class.airtrail_flights(user.id, producer: 'spec')

    expect { JobCommands.rehome!('imports.update_points_count', by: 'spec') }
      .to have_enqueued_job(Import::UpdatePointsCountJob).with(import.id)
    expect { JobCommands.rehome!('imports.airtrail_flights', by: 'spec') }
      .to have_enqueued_job(AirTrail::ImportFlightsJob).with(user.id)
    expect(JobOutbox.pending.count).to eq(0)
  end

  { update_points_count: [:import, Import::UpdatePointsCountJob],
    airtrail_flights: [:user, AirTrail::ImportFlightsJob] }.each do |command, (record, job)|
    it "keeps the pending #{command} command when rehome! cannot push it" do
      type = "imports.#{command}"
      job_owner!("command:#{type}", :oban)
      described_class.public_send(command, public_send(record).id, producer: 'spec')
      allow(job.queue_adapter).to receive(:enqueue).and_raise(RedisClient::CannotConnectError, 'redis down')

      expect(JobCommands.rehome!(type, by: 'spec'))
        .to eq({ moved: 0, left: 1, error: 'RedisClient::CannotConnectError' })
      expect(JobOutbox.pending.pluck(:command_type)).to eq([type])
    end
  end
end
