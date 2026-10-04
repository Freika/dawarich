# frozen_string_literal: true

require 'rails_helper'
require_relative 'normal_import_formats_support'

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
end
