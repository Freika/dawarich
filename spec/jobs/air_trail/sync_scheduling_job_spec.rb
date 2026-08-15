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
end
