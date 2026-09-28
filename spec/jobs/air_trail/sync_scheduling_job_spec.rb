# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::SyncSchedulingJob, type: :job do
  it 'enqueues an import job per user with airtrail configured' do
    configured = create(:user).tap do |u|
      u.update!(settings: u.settings.merge('airtrail_url' => 'https://a', 'airtrail_api_key' => 'k'))
    end
    create(:user)

    expect { described_class.perform_now }
      .to have_enqueued_job(AirTrail::ImportFlightsJob).with(configured.id).exactly(:once)
  end

  it 'skips users with blank airtrail settings' do
    create(:user).tap do |u|
      u.update!(settings: u.settings.merge('airtrail_url' => '', 'airtrail_api_key' => ''))
    end
    create(:user).tap do |u|
      u.update!(settings: u.settings.merge('airtrail_url' => 'https://a', 'airtrail_api_key' => nil))
    end

    expect { described_class.perform_now }.not_to have_enqueued_job(AirTrail::ImportFlightsJob)
  end

  it 'writes one outbox row per configured user while Oban owns the command' do
    job_owner!(ImportCommands::AIRTRAIL_FLIGHTS_KEY, :oban)
    configured = create(:user, settings: { 'airtrail_url' => 'https://a.example', 'airtrail_api_key' => 'k' })
    create(:user)

    described_class.perform_now

    expect(JobOutbox.pending.pluck(:aggregate_id)).to eq([configured.id])
    expect(AirTrail::ImportFlightsJob).not_to have_been_enqueued
  end
end
