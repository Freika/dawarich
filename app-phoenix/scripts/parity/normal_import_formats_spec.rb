# frozen_string_literal: true

require 'rails_helper'
require_relative 'normal_import_formats_support'
require_relative 'normal_import_json_support'
require_relative 'normal_import_photos_support'
require_relative 'normal_import_records_support'
require_relative 'normal_import_semantic_support'
require_relative 'normal_import_phone_support'
require_relative 'normal_import_kml_support'
require_relative 'normal_import_create_support'
require_relative 'normal_import_tcx_support'
require_relative 'normal_import_fit_support'
require_relative '../../../spec/support/fit_fixture_helper'

RSpec.describe 'Phoenix fixtures: normal Rails import formats' do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  it 'records the importer result independently of the native adapter' do
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      Time.use_zone(zone) do
        travel_to Time.utc(2026, 1, 15, 23, 30) do
          result = NormalImportFormatsSupport.capture_csv(zone)
          expect(result.fetch('detector')).to eq('csv')
          expect(result.fetch('import').fetch('doubles')).to eq(1)
          expect(result.fetch('import').fetch('raw_points')).to eq(2)
          expect(result.fetch('points').size).to eq(1)
          expect(result.fetch('points').first.fetch('lonlat')).to eq('POINT(12.4 51.3)')
          expect(result.fetch('notifications')).to eq([])
          expect(result.fetch('error')).to be_nil
          NormalImportFormatsSupport.write("csv_#{zone.tr('/', '_')}", result)
        end
      end
    end
    travel_to Time.utc(2026, 1, 15, 23, 30) do
      [false, true].each do |atomic|
        result = NormalImportFormatsSupport.capture_batch_failure(atomic)
        expect(result.fetch('points').size).to eq(atomic ? 0 : 1000)
        expect(result.fetch('import').fetch('raw_points')).to eq(atomic ? 0 : 1000)
        expect(result.fetch('notifications').size).to eq(atomic ? 0 : 1)
        expect(result.fetch('import').fetch('doubles')).to eq(0)
        name = atomic ? 'atomic_second_batch_failure' : 'csv_second_batch_failure'
        NormalImportFormatsSupport.write(name, result)
      end
    end
    detection = NormalImportFormatsSupport.capture_detection
    detection.each { |row| expect(row.fetch('source')).to eq(row.fetch('expected')) }
    NormalImportFormatsSupport.write('source_detection', detection)
    lexical = NormalImportFormatsSupport.capture_csv_lexical
    expect(lexical.find { |row| row['name'] == 'trailing_nil' }.fetch('fields')).to eq(['a', nil])
    expect(lexical.find { |row| row['name'] == 'quoted_empty' }.fetch('fields')).to eq(['', nil])
    expect(lexical.find { |row| row['name'] == 'unclosed' }.fetch('error').fetch('class'))
      .to eq('CSV::MalformedCSVError')
    NormalImportFormatsSupport.write('csv_lexical', lexical)
  end

  context 'CSV' do
    it 'records CSV importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.csv_import_cases.each do |name, bytes, zone, legacy|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !legacy)
          effects = []
          allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |method, user_id, timestamps:|
            effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
            method.call(user_id, timestamps:)
          end
          allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
            if options[:partial] == 'imports/table_row'
              effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
            end
            method.call(*args, **options)
          end
          result = NormalImportFormatsSupport.capture_csv_case(name, bytes, zone, legacy)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          expect(result.fetch('import').fetch('doubles')).to be_a(Integer)
          NormalImportFormatsSupport.write(name, result.merge('commands' => effects))
        end
      end
    end
  end

  context 'Polarsteps' do
    it 'records Polarsteps importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.polarsteps_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 13, Polarsteps::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Mobile photo library' do
    it 'records mobile photo library importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.mobile_photo_library_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 15, MobilePhotoLibrary::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Photos' do
    it 'records photo importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.photos_cases.each do |name, bytes, source|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          importer = source == 14 ? GooglePhotos::Importer : Photos::Importer
          result = NormalImportFormatsSupport.capture_json(name, bytes, 'UTC', source, importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Google Records' do
    it 'records Google Records preparation and importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_records_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 2, GoogleMaps::RecordsStorageImporter)
          prepared = NormalImportFormatsSupport.capture_records_preparation(bytes, zone)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(prepared).to include('prepared_points', 'device_tags')
          NormalImportFormatsSupport.write(name, result.merge(prepared))
        end
      end
    end
  end

  context 'Google Semantic History' do
    it 'records Google Semantic History importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_semantic_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 0, GoogleMaps::SemanticHistoryImporter)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('import').fetch('raw_points')).to eq(0)
          identities = { 'user_id' => 987_001, 'import_id' => 987_101 }
          NormalImportFormatsSupport.write(name, result.merge('identities' => identities))
        end
      end
    end
  end

  context 'Google Phone preparation' do
    it 'records Google Phone point preparation from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_phone_point_cases.each do |name, section, value, zone, legacy|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !legacy)
          result = NormalImportFormatsSupport.capture_phone_preparation(section, value, zone, legacy)
          expect(result).to include('prepared_points', 'section', 'input', 'error')
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Google Phone importer' do
    it 'records Google Phone importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_phone_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_phone_import(name, bytes, zone)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          commands = result['error'] ? [] : result['commands']
          identities = { 'user_id' => 987_001, 'import_id' => 987_101 }
          NormalImportFormatsSupport.write(name, result.merge('identities' => identities, 'commands' => commands,
                                                              'attempted_commands' => result['commands']))
        end
      end
    end
  end

  context 'KML' do
    it 'records KML importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.kml_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 9, Kml::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'TCX' do
    it 'records TCX importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.tcx_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 11, Tcx::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'motion_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'FIT importer' do
    it 'records FIT hierarchy and importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.fit_import_cases(self).each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 12, Fit::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data', 'status')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'velocity', 'motion_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'FIT decoder' do
    it 'records FIT decoder outcomes from fit4ruby' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.fit_reader_cases(self).each do |result|
          expect(result).to include('input', 'records', 'error')
          NormalImportFormatsSupport.write(result.fetch('name'), result.except('name'))
        end
      end
    end
  end

  context 'Whole create' do
    it 'records whole create and ZIP build failure effects' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.whole_create_cases.each do |options|
          result = NormalImportFormatsSupport.capture_whole_create(options)
          expect(result).to include('source_transition', 'parent', 'children', 'notifications', 'jobs', 'archive')
          expect(result.fetch('source_transition')).to eq(options.fetch(:expected_source))
          case options.fetch(:name)
          when 'kmz_plain'
            expect(result.fetch('children').map { |child| child.fetch('name') })
              .to eq(['_source.kmz (from plain.kmz)', 'first.KML (from plain.kmz)', 'last.kml (from plain.kmz)'])
          when 'kmz_wrapped'
            expect(result.fetch('points').map { |point| point.fetch('lonlat') }).to eq(['POINT(12.4 51.3)'])
            expect(result.fetch('kmz_leaf').fetch('name')).to eq('first.KML')
          when 'zip_later_child_failure', 'zip_extractor_later_child_failure'
            expect(result.fetch('parent').fetch('status')).to eq('failed')
            expect(result.fetch('children').map { |child| child.fetch('name') })
              .to eq(['existing-0.csv', 'existing-1.csv', 'existing-2.csv', 'first.csv (from limited.zip)'])
            expect(result.fetch('children').last.fetch('file')).to include('bytes', 'filename', 'content_type')
            expect(result.fetch('jobs').select { |job| job['type'] == 'Import::ProcessJob' }).to eq([])
          when 'csv_duplicate'
            expect(result.fetch('points')).to eq([])
            expect(result.fetch('parent')).to include('raw_points' => 2, 'doubles' => 2, 'status' => 'completed')
          when 'fit_failed_return'
            expect(result.fetch('parent').fetch('status')).to eq('failed')
          when 'v1_profile', 'v2_profile'
            expect(result.fetch('jobs')).to eq([{ 'type' => 'Users::ImportDataJob', 'args' => [987_101] }])
          when 'zip_known_preference'
            expect(result.fetch('children').map { |child| child.fetch('source') })
              .to eq(%w[google_records google_photos])
          end
          NormalImportFormatsSupport.write("whole_create/#{options.fetch(:name)}", result)
        end
      end
    end
  end

  context 'GeoJSON' do
    it 'records GeoJSON importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.geojson_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          effects = []
          allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |method, user_id, timestamps:|
            effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
            method.call(user_id, timestamps:)
          end
          allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
            if options[:partial] == 'imports/table_row'
              effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
            end
            method.call(*args, **options)
          end
          result = NormalImportFormatsSupport.capture_geojson(name, bytes, zone)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          commands = result['error'] ? [] : effects
          NormalImportFormatsSupport.write(name, result.merge('commands' => commands, 'attempted_commands' => effects))
        end
      end
    end
  end

  context 'OwnTracks' do
    it 'records OwnTracks importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.owntracks_cases.each do |name, bytes|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          effects = []
          allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |method, user_id, timestamps:|
            effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
            method.call(user_id, timestamps:)
          end
          allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
            if options[:partial] == 'imports/table_row'
              effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
            end
            method.call(*args, **options)
          end
          result = NormalImportFormatsSupport.capture_owntracks(name, bytes)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          expect(result.fetch('import').fetch('doubles')).to be_a(Integer)
          NormalImportFormatsSupport.write(name, result.merge('commands' => effects))
        end
      end
    end
  end
end
