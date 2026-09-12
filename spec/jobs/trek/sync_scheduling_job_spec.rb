# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::SyncSchedulingJob, type: :job do
  before do
    allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
  end

  it 'enqueues one job for each active TREK source' do
    active = create(:trip_source)
    create(:trip_source, status: :disabled)

    expect { described_class.perform_now }
      .to have_enqueued_job(Trek::SyncJob).with(active.id).exactly(:once)
  end
end
