# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google phone takeout import with invalid UTF-8 bytes' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, name: 'timeline.json', source: :google_phone_takeout) }

  let(:json_with_latin1_degree_signs) do
    latlng = "48.1351\xB0, 11.5820\xB0".dup.force_encoding(Encoding::BINARY)
    <<~JSON.dup.force_encoding(Encoding::BINARY)
      {"semanticSegments":[{"startTime":"2026-05-20T10:00:00.000Z","endTime":"2026-05-20T11:00:00.000Z","visit":{"topCandidate":{"placeLocation":{"latLng":"#{latlng}"}}}}]}
    JSON
  end

  def import_file
    file = Tempfile.new(['timeline', '.json'])
    file.binmode
    file.write(json_with_latin1_degree_signs)
    file.close

    GoogleMaps::PhoneTakeoutImporter.new(import, user.id, file.path).call
  ensure
    file&.unlink
  end

  it 'imports without raising on invalid byte sequences' do
    expect { import_file }.not_to raise_error
  end

  it 'parses the coordinates despite the broken degree signs' do
    import_file

    point = user.points.last
    expect(point).to be_present
    expect(point.lat).to be_within(0.0001).of(48.1351)
    expect(point.lon).to be_within(0.0001).of(11.5820)
  end

  it 'imports without raising when content comes from storage download' do
    downloader = instance_double(
      Imports::SecureFileDownloader, download_with_verification: json_with_latin1_degree_signs
    )
    allow(Imports::SecureFileDownloader).to receive(:new).and_return(downloader)

    expect { GoogleMaps::PhoneTakeoutImporter.new(import, user.id).call }.not_to raise_error
  end
end
