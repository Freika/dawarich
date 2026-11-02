# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A GPX import stored as unsupported still offers extraction', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def stale_import(source, name)
    import = create(:import, user: user, source: source, name: name)
    import.update_column(:additional_data_extraction_status,
                         Import.additional_data_extraction_statuses[:unsupported])
    import
  end

  it 'renders the extraction trigger instead of the unsupported notice' do
    import = stale_import(:gpx, 'favourites.gpx')

    get import_path(import)

    expect(response.body).not_to include('carry visits, named places')
    expect(response.body).to include("extraction-dialog-#{import.id}")
  end

  it 'does not badge it as unavailable above the trigger it now offers' do
    import = stale_import(:gpx, 'favourites.gpx')

    get import_path(import)

    expect(response.body).to include('<span class="badge badge-sm badge-ghost">Not extracted</span>')
    expect(response.body).not_to include('<span class="badge badge-sm badge-ghost">Not available</span>')
  end

  it 'keeps badging a format that genuinely has no adapter' do
    kml_import = stale_import(:kml, 'places.kml')

    get import_path(kml_import)

    expect(response.body).to include('<span class="badge badge-sm badge-ghost">Not available</span>')
  end

  it 'keeps hiding it for a format that genuinely has no adapter' do
    kml_import = stale_import(:kml, 'places.kml')

    get import_path(kml_import)

    expect(response.body).to include('carry visits, named places')
  end
end
