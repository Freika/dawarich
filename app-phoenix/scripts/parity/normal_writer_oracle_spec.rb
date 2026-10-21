# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixture: points persisted by Imports::BulkInsertable for normal import rows' do
  self.use_transactional_tests = false

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/imports') }
  let(:connection) { ActiveRecord::Base.connection }
  let(:stamp) { Time.utc(2026, 1, 1) }

  let(:columns) do
    %w[lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id
       ssid bssid topic battery_status connection trigger inrids in_regions motion_data
       course course_accuracy raw_data]
  end

  let(:writer) do
    Class.new do
      include Imports::BulkInsertable
      attr_reader :import

      def initialize(import) = @import = import
      def write(rows) = bulk_insert_points(rows)
      def atomic_bulk_insert? = true
    end
  end

  def decode_tags(value)
    if value.is_a?(Hash) && value.keys == ['__float__']
      { 'Infinity' => Float::INFINITY, '-Infinity' => -Float::INFINITY,
        'NaN' => Float::NAN }.fetch(value.fetch('__float__'))
    elsif value.is_a?(Hash) && value.keys == ['__symbol_pairs__']
      value.fetch('__symbol_pairs__').to_h { |key, item| [key.to_sym, decode_tags(item)] }
    elsif value.is_a?(Hash) && value.keys == ['__bytes__']
      [value.fetch('__bytes__')].pack('H*').force_encoding(Encoding::UTF_8)
    elsif value.is_a?(Hash) && value.keys == ['__symbol_hash__']
      value.fetch('__symbol_hash__').transform_keys(&:to_sym).transform_values { |v| decode_tags(v) }
    elsif value.is_a?(Hash)
      value.transform_values { |v| decode_tags(v) }
    elsif value.is_a?(Array)
      value.map { |v| decode_tags(v) }
    else
      value
    end
  end

  def reset_fixtures!
    raise 'wrong oracle database' unless connection.current_database.start_with?('dawarich_test_')

    ActiveStorage::Attachment.find_each(&:purge)
    FixtureCleanup.delete!(%w[users imports points point_sources])
  end

  def owner!
    user = connection.select_value(<<~SQL).to_i
      INSERT INTO users(email,created_at,updated_at)
      VALUES ('normal-oracle@example.invalid',now(),now()) RETURNING id
    SQL
    id = connection.select_value(<<~SQL).to_i
      INSERT INTO imports(user_id,name,source,created_at,updated_at)
      VALUES (#{user},'oracle.rec',1,now(),now()) RETURNING id
    SQL
    [user, id]
  end

  def attempt(import, rows)
    { 'inserted' => writer.new(import).write(rows), 'error' => nil }
  rescue StandardError => e
    { 'inserted' => nil, 'error' => { 'class' => e.class.name, 'message' => error_message(e) } }
  end

  def error_message(error)
    error.message.start_with?('PG::') ? error.message.lines.first.chomp : error.message
  end

  def points(id)
    sql = columns.map do |c|
      c == 'lonlat' ? 'ST_AsText(lonlat::geometry) AS lonlat' : connection.quote_column_name(c)
    end.join(',')
    connection.select_all("SELECT #{sql} FROM points WHERE import_id=#{id} ORDER BY id").to_a.each do |point|
      %w[motion_data raw_data].each { |key| point[key] = JSON.parse(point[key]) if point[key].is_a?(String) }
      %w[inrids in_regions].each { |key| point[key] = Point.type_for_attribute(key).deserialize(point[key]) }
      %w[altitude_decimal course course_accuracy].each { |key| point[key] = point[key]&.to_s }
    end
  end

  def sources
    connection.select_all(<<~SQL).to_a.each do |source|
      SELECT digest,tracker_id,topic,ssid,bssid,connection,trigger,battery_status,
             array_to_json(inrids) AS inrids,array_to_json(in_regions) AS in_regions
      FROM point_sources ORDER BY id
    SQL
      %w[inrids in_regions].each { |key| source[key] = JSON.parse(source[key]) if source[key].is_a?(String) }
    end
  end

  def capture(example)
    reset_fixtures!
    user, id = owner!
    attrs = { lonlat: 'POINT(12.4 51.3)', timestamp: 1_700_000_000, altitude: 12.75, altitude_decimal: 12.75,
              velocity: 1.2, tracker_id: 'normal-oracle', import_id: id, user_id: user,
              created_at: stamp, updated_at: stamp }
    rows = example.fetch('rows', [example.fetch('attributes', {})]).map do |row|
      attrs.merge(decode_tags(row).transform_keys(&:to_sym))
    end
    outcome = attempt(Import.find(id), rows)
    { 'name' => example['name'], 'attributes' => example['attributes'], 'rows' => example['rows'],
      'inserted' => outcome['inserted'], 'error' => outcome['error'],
      'counters' => connection.select_rows("SELECT raw_points,doubles FROM imports WHERE id=#{id}").first,
      'points' => points(id), 'sources' => sources }
  end

  it 'cleans archive attachments before resetting fixture identities' do
    reset_fixtures!
    user, = owner!
    archive = create(:points_raw_data_archive, user: User.find(user))
    blob = archive.file.blob
    archive_id = archive.id
    reset_fixtures!
    expect(ActiveStorage::Attachment.where(blob_id: blob.id)).to be_empty
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect(blob.service.exist?(blob.key)).to be(false)
    user, = owner!
    restored = Points::RawDataArchive.create!(
      id: archive_id, user_id: user, year: 2026, month: 1, chunk_number: 1,
      point_count: 1, point_ids_checksum: 'synthetic-cleanup', archived_at: stamp
    )
    expect(restored.file).not_to be_attached
  ensure
    reset_fixtures!
  end

  it 'records every input case from a real PostgreSQL write' do
    inputs = JSON.parse(File.read(dir.join('normal_writer_inputs.json')))
    output = inputs.map { |example| capture(example) }
    expect(output).to all(include('counters', 'points', 'sources', 'error'))
    expect(output.map { |item| item.fetch('counters').size }).to all(eq(2))
    FixtureRecording.verify(dir.join('rails_normal_writer_oracle.json'), JSON.pretty_generate(output))
    expect(output.size).to eq(inputs.size)
  ensure
    reset_fixtures!
  end
end
