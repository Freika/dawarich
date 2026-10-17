# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix wave 6 fixtures' do
  include ActiveSupport::Testing::TimeHelpers

  secret = 'wave6-fixture-secret'

  around do |example|
    travel_to(Time.utc(2026, 4, 15, 10)) { example.run }
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ARCHIVE_ENCRYPTION_KEY').and_return(secret)
    allow(PointsChannel).to receive(:broadcast_to)
    Points::RawData::Encryption.reset!
  end

  after { Points::RawData::Encryption.reset! }

  it 'writes or matches raw_archive.json' do
    verify_fixture('raw_archive.json', raw_archive_fixture(secret)) do |committed, fresh|
      gzip = Points::RawData::Encryption.decrypt(committed.fetch('message'))

      expect(committed.fetch('secret')).to eq(secret)
      expect(committed.fetch('message').split('--')[1]).to eq(committed.fetch('iv_b64'))
      expect(Base64.strict_encode64(gzip)).to eq(committed.fetch('gzip_b64'))
      expect(gunzip_lines(gzip)).to eq(committed.fetch('lines'))
      expect(deterministic_archive(fresh)).to eq(deterministic_archive(committed))
    end
  end

  it 'writes or matches extractors.json' do
    verify_fixture('extractors.json', extractors_fixture)
  end

  it 'writes or matches sql_fragments.json' do
    verify_fixture('sql_fragments.json', sql_fragments_fixture)
  end

  private

  def fixture_dir
    Rails.root.join('app-phoenix/test/fixtures/wave6')
  end

  def verify_fixture(filename, structure)
    path = fixture_dir.join(filename)
    json = Oj.dump(structure, mode: :strict, float_precision: 0, indent: 2)

    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(fixture_dir)
      File.write(path, "#{json}\n")
    elsif block_given?
      yield JSON.parse(path.read), JSON.parse(json)
    else
      expect(JSON.parse(json)).to eq(JSON.parse(path.read))
    end
  end

  def leipzig_raw_data
    [
      { 'alt' => 110.55, 'note' => '<b>&</b>', 'city' => 'Leipzig' },
      { 'properties' => { 'altitude' => '99.4', 'motion' => ['walking'] },
        'geometry' => { 'coordinates' => [12.37, 51.34, 101] } },
      { 'altitudeMeters' => 87, 'activity' => { 'type' => 'STILL' },
        'nested' => { 'f' => 0.30000000000000004, 'big' => 12_345_678_901_234_567_890 } },
      { 'tst' => 1_700_000_000, 'm' => 2, '_type' => 'location', 'name' => 'Straße ü' }
    ]
  end

  def raw_archive_fixture(secret)
    user = create(:user, id: 7)
    lonlats = ['POINT(12.3731 51.3397)', 'POINT(12.3745 51.3402)', 'POINT(12.376 51.341)', 'POINT(12.3772 51.3418)']
    [9, 10, 100, 1001].zip(lonlats, leipzig_raw_data).each_with_index do |(id, lonlat, raw_data), index|
      create(:point, id:, user:, lonlat:, raw_data:, timestamp: Time.utc(2026, 1, 10, 8).to_i + (index * 600))
    end

    Points::RawData::Archiver.new.archive_specific_month(user.id, 2026, 1)
    archive = Points::RawDataArchive.find_by!(user_id: user.id)
    message = archive.file.download
    gzip = Points::RawData::Encryption.decrypt(message)
    expect(archive.file.blob.key).to match(%r{\Araw_data_archives/7/2026/01/001\.jsonl\.gz\.enc\z})

    {
      'secret' => secret,
      'storage_key' => archive.file.blob.key,
      'filename' => archive.file.blob.filename.to_s,
      'metadata' => archive.metadata,
      'point_count' => archive.point_count,
      'point_ids_checksum' => archive.point_ids_checksum,
      'message' => message,
      'iv_b64' => message.split('--')[1],
      'gzip_b64' => Base64.strict_encode64(gzip),
      'lines' => gunzip_lines(gzip),
      'points' => archived_points(user),
      'sample_indices' => [1, 100, 101, 2500, 50_000].map do |count|
        { 'count' => count, 'indices' => Points::RawData::Verifier.new.send(:build_sample_indices, count).sort }
      end
    }
  end

  def archived_points(user)
    Point.where(user:).order(:id).pluck(:id, Arel.sql('ST_AsText(lonlat)'), :timestamp, :raw_data).map do |row|
      %w[id lonlat timestamp raw_data].zip(row).to_h
    end
  end

  def gunzip_lines(gzip)
    Zlib::GzipReader.new(StringIO.new(gzip)).each_line.map(&:chomp)
  end

  def deterministic_archive(archive)
    archive.except('message', 'iv_b64', 'gzip_b64')
           .merge('metadata' => archive.fetch('metadata').except('content_checksum'))
  end

  def extractors_fixture
    {
      'motion' => motion_cases.map do |raw_data|
        { 'raw_data' => raw_data, 'expected' => Points::MotionDataExtractor.from_raw_data(raw_data) }
      end,
      'altitude' => altitude_cases.map do |raw_data|
        { 'raw_data' => raw_data, 'expected' => Points::AltitudeExtractor.from_raw_data(raw_data) }
      end,
      'altitude_casts' => altitude_casts,
      'to_f' => ['12.5', ' 7', '1_000', '1e3', '.5', '-3.2abc', 'abc', '', '1.', '0x1A', '+4', '1__0'].map do |input|
        { 'input' => input, 'expected' => input.to_f }
      end,
      'place_names' => place_name_cases.map do |properties|
        { 'properties' => properties,
          'built' => Visits::Names::Builder.build_from_properties(properties),
          'geocoder' => DataMigrations::BackfillPlaceNameLocksJob.new.send(:geocoder_style_name, properties) }
      end,
      'country_aliases' => Countries::NameAliases::ALIASES.to_a
    }
  end

  def motion_cases
    [
      { 'properties' => { 'motion' => ['driving'], 'activity' => 'automotive_navigation', 'action' => false } },
      { 'properties' => { 'speed' => 3 }, 'activity' => 'WALKING' },
      { 'activityRecord' => { 'probableActivities' => [{ 'type' => 'STILL', 'confidence' => 95 }] } },
      { 'activities' => [{ 'activityType' => 'WALKING', 'probability' => 0.9 }],
        'waypointPath' => { 'travelMode' => 'WALK' } },
      { 'm' => 2, '_type' => 'location', 'tst' => 1_700_000_000 },
      { 'm' => 1 },
      {},
      { 'x' => 1 }
    ]
  end

  def altitude_cases
    leipzig_raw_data + [
      { 'ele' => '12.5m' },
      { 'properties' => { 'altitude' => '' }, 'geometry' => { 'coordinates' => [1, 2, 0] } },
      { 'altitude' => nil },
      { 'x' => 1 }
    ]
  end

  def altitude_casts
    user = create(:user)
    [110.55, 1.005, 2.675, -0.125, 99.4, 87.0, 12_345.678, 0.004999].map do |value|
      point = create(:point, user:, lonlat: 'POINT(12.3731 51.3397)')
      Point.upsert_all([{ id: point.id, altitude: value, altitude_decimal: value }],
                       unique_by: :id, update_only: %i[altitude altitude_decimal])
      altitude, decimal = Point.where(id: point.id)
                               .pick(:altitude, Arel.sql('altitude_decimal::text AS altitude_decimal_text'))
      { 'value' => value, 'altitude' => altitude, 'altitude_decimal' => decimal }
    end
  end

  def place_name_cases
    [
      { 'name' => 'Zoo Leipzig', 'street' => 'Pfaffendorfer Straße', 'housenumber' => '29', 'postcode' => '04105',
        'city' => 'Leipzig', 'state' => 'Saxony', 'country' => 'Germany', 'osm_value' => 'zoo' },
      { 'name' => 'Leipzig Hauptbahnhof', 'street' => 'Willy-Brandt-Platz', 'housenumber' => 5,
        'postcode' => '04109', 'city' => 'Leipzig', 'osm_value' => 'bus_stop' },
      { 'name' => 'yes', 'street' => 'Augustusplatz', 'city' => 'Leipzig', 'osm_value' => 'square' },
      { 'name' => '   ', 'street' => 'Grimmaische Straße', 'city' => 'Leipzig', 'osm_value' => 'pedestrian' },
      { 'name' => 'Leipzig', 'city' => 'Leipzig', 'state' => 'Saxony', 'osm_value' => 'city' },
      { 'name' => 'Thomaskirche', 'street' => 'Thomaskirchhof', 'housenumber' => '18', 'postcode' => '04109',
        'city' => 'Leipzig' },
      { 'name' => nil, 'street' => 'Karl-Liebknecht-Straße', 'housenumber' => '1', 'postcode' => '04107',
        'city' => 'Leipzig', 'osm_value' => 'house' }
    ]
  end

  def sql_fragments_fixture
    {
      'digest_points' => PointSource.digest_sql('points'),
      'digest_p' => PointSource.digest_sql('p'),
      'combo_column_list' => DataMigrations::BackfillPointDimensionsJob.new.send(:combo_column_list),
      'null_island' => Points::NullIsland.sql_predicate
    }
  end
end
