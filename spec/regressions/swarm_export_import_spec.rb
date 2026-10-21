# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'Foursquare Swarm data export import' do
  let(:user) { create(:user) }
  let(:checkins_path) { file_fixture('swarm/checkins1.json').to_s }

  describe 'source detection' do
    it 'recognises a checkins file' do
      expect(Imports::SourceDetector.new_from_file_header(checkins_path).detect_source).to eq(:swarm)
    end

    it 'recognises a checkins file too large to parse from the header' do
      big = Rails.root.join('tmp', "swarm_big_#{SecureRandom.hex(4)}.json")
      item = JSON.parse(File.read(checkins_path))['items'].first
      big.write({ 'count' => 400, 'items' => Array.new(400) { item } }.to_json)

      expect(Imports::SourceDetector.new_from_file_header(big.to_s).detect_source).to eq(:swarm)
    ensure
      FileUtils.rm_f(big)
    end
  end

  describe 'full export archive' do
    let(:archive) { create(:import, user:, name: 'foursquare-export.zip') }
    let(:zip_path) do
      path = Rails.root.join('tmp', "swarm_export_#{SecureRandom.hex(4)}.zip").to_s
      Zip::File.open(path, create: true) do |zip|
        zip.add('checkins1.json', checkins_path)
        zip.get_output_stream('checkins1.csv') { |f| f.write("id,createdAt\n1,2024-05-04 10:00:00\n") }
        zip.get_output_stream('tips.json') { |f| f.write('{"count":0,"items":[]}') }
        zip.get_output_stream('users.json') { |f| f.write('{"count":1,"items":[{"id":"1"}]}') }
        zip.get_output_stream('photos.json') { |f| f.write('{"count":0,"items":[]}') }
        zip.get_output_stream('readme.html') { |f| f.write('<html></html>') }
      end
      path
    end

    after { FileUtils.rm_f(zip_path) }

    it 'does not count the photo folder against the archive limits' do
      stub_const('Imports::ZipExtractor::MAX_FILES', 5)
      Zip::File.open(zip_path) do |zip|
        5.times { |i| zip.get_output_stream("pix/photo#{i}.jpg") { |f| f.write('jpeg') } }
      end

      Imports::ZipExtractor.new(archive, user.id, zip_path).call

      expect(user.imports.pluck(:source)).to eq(['swarm'])
    end

    it 'imports only the checkins files, tagged as Swarm' do
      Imports::ZipExtractor.new(archive, user.id, zip_path).call

      expect(user.imports.pluck(:name, :source)).to eq([['checkins1.json (from foursquare-export.zip)', 'swarm']])
    end
  end

  describe 'visit extraction' do
    let(:import) do
      create(:import, user:, source: :swarm, name: 'checkins1.json').tap do |import|
        import.file.attach(io: File.open(checkins_path), filename: 'checkins1.json', content_type: 'application/json')
      end
    end

    before { EnhancedImport::ExtractJob.new.perform(import.id) }

    def visit_at(hour, minute = 0)
      Visit.find_by(import_id: import.id, started_at: Time.utc(2024, 5, 4, hour, minute))
    end

    it 'turns every venue check-in into a visit' do
      expect(import.reload.additional_data_extraction_completed?).to be true
      expect(Visit.where(import_id: import.id).count).to eq(3)
    end

    it 'ends a visit at the next check-in' do
      expect(visit_at(10).ended_at).to eq(Time.utc(2024, 5, 4, 10, 45))
      expect(visit_at(10).duration).to eq(45)
    end

    it 'caps a visit at two hours when the next check-in is later' do
      expect(visit_at(10, 45).ended_at).to eq(Time.utc(2024, 5, 4, 12, 45))
    end

    it 'gives a visit one minute when the next check-in is at the same moment' do
      expect(visit_at(15).duration).to eq(1)
    end

    it 'stores one place per Foursquare venue' do
      places = Place.where(import_id: import.id)

      expect(places.pluck(:name)).to contain_exactly('Café Kandler', 'Thomaskirche')
      expect(places.map { |p| p.geodata['external_place_id'] })
        .to contain_exactly('foursquare:4b0588a1f964a520c0d922e3', 'foursquare:4adcda7ef964a520a64921e3')
    end
  end
end
