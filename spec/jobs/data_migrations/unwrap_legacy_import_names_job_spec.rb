# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::UnwrapLegacyImportNamesJob, type: :job do
  let(:user) { create(:user) }

  def legacy_import(name, blob_filename: name, metadata: {}, owner: user)
    import = create(:import, user: owner, name:, skip_background_processing: true)
    import.file.attach(io: StringIO.new('PK'), filename: blob_filename, content_type: 'application/zip',
                       metadata:)
    import
  end

  it 'drops the upload wrapper extension from legacy GPX and KML import names' do
    gpx = legacy_import('morning-ride.gpx.zip')
    kml = legacy_import('route.kml.zip')

    described_class.perform_now

    expect(gpx.reload.name).to eq('morning-ride.gpx')
    expect(kml.reload.name).to eq('route.kml')
  end

  it 'restores the inner extension of a legacy timestamp-suffixed name' do
    import = legacy_import('route.gpx_20260801_120000.zip', blob_filename: 'route.gpx.zip')

    described_class.perform_now

    expect(import.reload.name).to eq('route_20260801_120000.gpx')
  end

  it 'keeps genuine archives, uploads marked as not wrapped, and names the user changed' do
    archive = legacy_import('tracks.zip')
    unwrapped = legacy_import('export.gpx.zip', metadata: { 'dawarich_client_wrapped' => false })
    renamed = legacy_import('My holiday.zip', blob_filename: 'holiday.gpx.zip')

    described_class.perform_now

    expect(archive.reload.name).to eq('tracks.zip')
    expect(unwrapped.reload.name).to eq('export.gpx.zip')
    expect(renamed.reload.name).to eq('My holiday.zip')
  end

  it 'keeps the legacy name when the user already has an import with the unwrapped name' do
    create(:import, user:, name: 'route.kml', skip_background_processing: true)
    legacy = legacy_import('route.kml.zip')
    other_user_legacy = legacy_import('route.kml.zip', owner: create(:user))

    described_class.perform_now

    expect(legacy.reload.name).to eq('route.kml.zip')
    expect(other_user_legacy.reload.name).to eq('route.kml')
  end

  it 'skips imports without an attached file' do
    import = create(:import, user:, name: 'route.kml.zip', skip_background_processing: true)

    expect { described_class.perform_now }.not_to raise_error
    expect(import.reload.name).to eq('route.kml.zip')
  end
end
