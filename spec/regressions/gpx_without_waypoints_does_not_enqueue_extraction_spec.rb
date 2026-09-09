# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A GPX holding no waypoints never enqueues an extraction job' do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def complete(raw_data)
    import = create(:import, user: user, source: :gpx, name: "track-#{SecureRandom.hex(4)}.gpx",
                             raw_data: raw_data, status: :processing)
    import.update!(status: :completed)
    import
  end

  it 'skips the job when the importer counted trackpoints and no waypoints' do
    expect { complete('trackpoints_seen' => 40) }.not_to have_enqueued_job(EnhancedImport::ExtractJob)
  end

  it 'still enqueues when waypoints were counted' do
    expect { complete('trackpoints_seen' => 40, 'waypoints_seen' => 2) }
      .to have_enqueued_job(EnhancedImport::ExtractJob)
  end

  it 'still enqueues for an import that predates element counting' do
    expect { complete(nil) }.to have_enqueued_job(EnhancedImport::ExtractJob)
  end
end
