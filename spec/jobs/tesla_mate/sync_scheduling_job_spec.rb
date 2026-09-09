# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::SyncSchedulingJob, type: :job do
  it 'enqueues one sync for every user with a TeslaMateApi URL' do
    configured = create(:user).tap do |user|
      user.update!(settings: user.settings.merge('teslamate_url' => 'https://teslamate.example'))
    end
    create(:user)

    expect { described_class.perform_now }
      .to have_enqueued_job(TeslaMate::SyncJob).with(configured.id).exactly(:once)
  end

  it 'skips blank TeslaMateApi URLs' do
    create(:user).tap { |user| user.update!(settings: user.settings.merge('teslamate_url' => '')) }

    expect { described_class.perform_now }.not_to have_enqueued_job(TeslaMate::SyncJob)
  end
end
