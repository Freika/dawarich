# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX extraction does not re-read a file the importer found no waypoints in' do
  let(:user) { create(:user) }

  def build_import(raw_data)
    import = create(:import, user: user, source: :gpx, name: 'gpx_waypoints_only.gpx', raw_data: raw_data)
    import.file.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/gpx/gpx_waypoints_only.gpx')),
      filename: 'gpx_waypoints_only.gpx',
      content_type: 'application/gpx+xml'
    )
    import
  end

  it 'extracts nothing when the import recorded trackpoints and no waypoints' do
    import = build_import('trackpoints_seen' => 12)

    expect { EnhancedImport::ExtractJob.new.perform(import.id) }
      .not_to(change { Place.where(user_id: user.id).count })
  end

  it 'never opens the attached file in that case' do
    import = build_import('trackpoints_seen' => 12)
    allow(File).to receive(:open).and_call_original

    EnhancedImport::ExtractJob.new.perform(import.id)

    expect(File).not_to have_received(:open).with(/\.gpx\z/, 'rb')
  end

  it 'still extracts when the import recorded waypoints alongside a track' do
    import = build_import('trackpoints_seen' => 12, 'waypoints_seen' => 3)

    expect { EnhancedImport::ExtractJob.new.perform(import.id) }
      .to change { Place.where(user_id: user.id).count }.by(3)
  end

  it 'still extracts for an import that predates element counting' do
    import = build_import(nil)

    expect { EnhancedImport::ExtractJob.new.perform(import.id) }
      .to change { Place.where(user_id: user.id).count }.by(3)
  end
end
