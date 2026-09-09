# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX waypoint shapes the extractor has to survive' do
  let(:user) { create(:user) }

  def extract(io, filename, content_type)
    import = create(:import, user: user, source: :gpx, name: filename)
    import.file.attach(io: io, filename: filename, content_type: content_type)
    EnhancedImport::ExtractJob.new.perform(import.id)
    import
  end

  describe 'a waypoint carrying no name' do
    let(:body) do
      <<~GPX
        <?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
        <gpx version="1.1" creator="OsmAnd~" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="51.3402000" lon="12.3712000"><type>Food</type></wpt>
        </gpx>
      GPX
    end

    it 'still creates the place rather than aborting the extraction' do
      import = extract(StringIO.new(body), 'nameless.gpx', 'application/gpx+xml')

      expect(import.reload).to be_additional_data_extraction_completed
      expect(Place.where(user_id: user.id).pluck(:name)).to eq(['Unknown'])
    end
  end

  describe 'a favourites file delivered inside a zip' do
    let(:zip_path) { Rails.root.join("tmp/gpx_waypoints_#{SecureRandom.hex(4)}.zip") }

    before do
      Zip::File.open(zip_path, create: true) do |zip|
        zip.add('favourites.gpx', Rails.root.join('spec/fixtures/files/gpx/gpx_waypoints_only.gpx'))
      end
    end

    after { FileUtils.rm_f(zip_path) }

    it 'unwraps the archive and extracts the waypoints inside it' do
      extract(File.open(zip_path), 'favourites.zip', 'application/zip')

      expect(Place.where(user_id: user.id).count).to eq(3)
    end
  end
end
