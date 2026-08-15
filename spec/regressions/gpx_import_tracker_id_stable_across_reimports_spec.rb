# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'GPX import tracker_id is stable across re-imports of the same device' do
  let(:user) { create(:user) }

  let(:tempfiles) { [] }

  after do
    tempfiles.each do |f|
      f.close!
    rescue StandardError
      nil
    end
  end

  def write_gpx(filename, base_time, trk_name: 'Morning Run', trk_src: 'Garmin Forerunner 245')
    points = (0..3).map do |i|
      t = (base_time + (i * 60)).utc.iso8601
      %(<trkpt lat="#{52.52 + (i * 0.0001)}" lon="#{13.405 + (i * 0.0001)}"><time>#{t}</time></trkpt>)
    end.join("\n")

    trk_inner = []
    trk_inner << "<name>#{trk_name}</name>" if trk_name
    trk_inner << "<src>#{trk_src}</src>" if trk_src
    trk_inner << "<trkseg>#{points}</trkseg>"

    content = <<~GPX
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
        <trk>
          #{trk_inner.join("\n      ")}
        </trk>
      </gpx>
    GPX

    file = Tempfile.new([filename, '.gpx'])
    file.write(content)
    file.close
    tempfiles << file
    file.path
  end

  let(:import_a) { create(:import, user: user, name: 'a.gpx', source: 'gpx') }
  let(:import_b) { create(:import, user: user, name: 'b.gpx', source: 'gpx') }

  def attach_and_import(import, path, filename)
    import.file.attach(
      io: File.open(path),
      filename: filename,
      content_type: 'application/gpx+xml'
    )
    Gpx::TrackImporter.new(import, user.id, path).call
  end

  it 'two imports of the same device on different days produce identical tracker_ids when <src> present' do
    path_a = write_gpx('day_a', 2.hours.ago)
    path_b = write_gpx('day_b', 4.hours.ago)

    attach_and_import(import_a, path_a, 'day_a.gpx')
    attach_and_import(import_b, path_b, 'day_b.gpx')

    ids_a = Point.where(import_id: import_a.id).pluck(:tracker_id).uniq
    ids_b = Point.where(import_id: import_b.id).pluck(:tracker_id).uniq

    expect(ids_a).to eq(ids_b)
    expect(ids_a.first).to start_with('gpx-')
    expect(ids_a.first).not_to include(import_a.id.to_s)
    expect(ids_a.first).not_to include(import_b.id.to_s)
  end

  it 'prefers <src> over <name> for device identity' do
    path = write_gpx('identity', 1.hour.ago)
    attach_and_import(import_a, path, 'identity.gpx')

    tracker_id = Point.where(import_id: import_a.id).pick(:tracker_id)
    name_hash = Digest::SHA1.hexdigest('Morning Run')[0, 16]
    src_hash = Digest::SHA1.hexdigest('Garmin Forerunner 245')[0, 16]

    expect(tracker_id).to include(src_hash)
    expect(tracker_id).not_to include(name_hash)
  end

  it 'differentiates two devices sharing a <trk><name> via import.name when <src> is absent' do
    path_a = write_gpx('shared_a', 2.hours.ago, trk_src: nil)
    path_b = write_gpx('shared_b', 4.hours.ago, trk_src: nil)

    attach_and_import(import_a, path_a, 'shared_a.gpx')
    attach_and_import(import_b, path_b, 'shared_b.gpx')

    id_a = Point.where(import_id: import_a.id).pick(:tracker_id)
    id_b = Point.where(import_id: import_b.id).pick(:tracker_id)

    expect(id_a).not_to eq(id_b)
    expect(id_a).to start_with('gpx-')
    expect(id_b).to start_with('gpx-')
  end
end
