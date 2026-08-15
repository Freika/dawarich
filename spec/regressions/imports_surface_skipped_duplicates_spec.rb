# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports surface skipped duplicates' do
  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx') }

  def build_import_with(file_path, name:, source: :gpx)
    import = create(:import, user: user, name: name, source: source, skip_background_processing: true)
    import.file.attach(
      io: File.open(file_path, 'rb'),
      filename: name,
      content_type: 'application/gpx+xml'
    )
    import
  end

  context 'with no pre-existing points' do
    it 'imports normally and leaves doubles at zero' do
      import = build_import_with(file_path, name: 'happy_path.gpx')

      expect { Imports::Create.new(user, import).call }
        .to change { import.reload.points.count }.from(0).to(10)

      expect(import.doubles).to eq(0)
      expect(import.raw_points).to eq(10)
      expect(user.notifications.count).to eq(0)
    end
  end

  context 'when every point in the file already exists in the timeline' do
    before do
      reader = Nokogiri::XML(File.read(file_path))
      reader.remove_namespaces!
      reader.xpath('//trkpt').each do |node|
        lon = node['lon']
        lat = node['lat']
        ts  = Time.zone.parse(node.at_xpath('time').text).to_i
        Point.create!(user: user, lonlat: "POINT(#{lon} #{lat})", timestamp: ts, raw_data: { seeded: true })
      end
    end

    it 'inserts no points, records every row as a duplicate, and notifies the user' do
      import = build_import_with(file_path, name: 'all_duplicates.gpx')

      Imports::Create.new(user, import).call

      import.reload
      expect(import.points.count).to eq(0)
      expect(import.raw_points).to eq(10)
      expect(import.doubles).to eq(10)
      expect(import.status).to eq('completed')

      notification = user.notifications.order(:created_at).last
      expect(notification).not_to be_nil
      expect(notification.kind).to eq('info')
      expect(notification.title).to eq('Import completed with no new points')
      expect(notification.content).to include('all_duplicates.gpx')
      expect(notification.content).to include('10 points')
    end
  end

  context 'when some points already exist and some are new' do
    before do
      reader = Nokogiri::XML(File.read(file_path))
      reader.remove_namespaces!
      reader.xpath('//trkpt').first(4).each do |node|
        lon = node['lon']
        lat = node['lat']
        ts  = Time.zone.parse(node.at_xpath('time').text).to_i
        Point.create!(user: user, lonlat: "POINT(#{lon} #{lat})", timestamp: ts, raw_data: { seeded: true })
      end
    end

    it 'inserts only the new points, records the rest as duplicates, and does not notify' do
      import = build_import_with(file_path, name: 'partial_overlap.gpx')

      Imports::Create.new(user, import).call

      import.reload
      expect(import.points.count).to eq(6)
      expect(import.raw_points).to eq(10)
      expect(import.doubles).to eq(4)
      expect(user.notifications.where(title: 'Import completed with no new points')).to be_empty
    end
  end

  context 'when an import is retried after a prior partial run' do
    it 'resets raw_points and doubles when processing starts' do
      import = build_import_with(file_path, name: 'retry.gpx')
      import.update_columns(raw_points: 999, doubles: 555)

      Imports::Create.new(user, import).call

      import.reload
      expect(import.raw_points).to eq(10)
      expect(import.doubles).to eq(0)
    end
  end
end
