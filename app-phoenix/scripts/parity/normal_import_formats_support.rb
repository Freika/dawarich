# frozen_string_literal: true

module NormalImportFormatsSupport
  DIR = Rails.root.join('app-phoenix/test/fixtures/imports/formats')
  POINT_COLUMNS = %w[lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping
                     tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data
                     course course_accuracy raw_data].freeze
  IMPORT_COLUMNS = %w[source raw_points doubles processed raw_data status error_message].freeze

  class BatchWriter
    include Imports::BulkInsertable
    attr_reader :import

    def initialize(import, atomic)
      @import = import
      @atomic = atomic
    end

    def write(rows) = bulk_insert_points(rows)
    def atomic_bulk_insert? = @atomic
    def importer_name = 'CSV'
  end

  module_function

  def write(name, value)
    FileUtils.mkdir_p(DIR)
    File.write(DIR.join("#{name}.json"), "#{JSON.pretty_generate(value)}\n")
  end

  def capture_csv(zone)
    output = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      user, import = owner!(zone)
      input = "latitude,longitude,timestamp,altitude,tracker_id\n51.3,12.4,2026-01-15 23:30:00,12.75,oracle\n"
      FileUtils.mkdir_p(DIR)
      path = DIR.join('csv_valid.csv')
      File.write(path, input)
      importer = Csv::Importer.new(import, user.id, path.to_s)
      2.times { importer.call }
      output = snapshot(import).merge('zone' => zone, 'locale' => 'en', 'input' => path.basename.to_s,
                                      'detector' => Imports::SourceDetector.new_from_file_header(path).detect_source.to_s,
                                      'error' => nil)
      raise ActiveRecord::Rollback
    end
    output
  end

  def owner!(zone, locale = 'en')
    connection = ActiveRecord::Base.connection
    settings = connection.quote({ 'timezone' => zone, 'locale' => locale }.to_json)
    connection.execute(<<~SQL)
      INSERT INTO users(id,email,settings,created_at,updated_at)
      VALUES (987001,'normal-formats@example.invalid',#{settings},'2026-01-15 23:30:00','2026-01-15 23:30:00')
    SQL
    connection.execute(<<~SQL)
      INSERT INTO imports(id,user_id,name,source,created_at,updated_at)
      VALUES (987101,987001,'oracle.csv',10,'2026-01-15 23:30:00','2026-01-15 23:30:00')
    SQL
    [User.find(987_001), Import.find(987_101)]
  end

  def capture_batch_failure(atomic)
    _, import = owner!('UTC', 'de')
    batches = [1000, 1].each_with_index.map do |size, batch|
      size.times.map do |i|
        { lonlat: 'POINT(12.4 51.3)', timestamp: Time.current.to_i + i + batch * 1000,
          altitude: 12, altitude_decimal: batch.zero? ? 12.75 : 100_000_000,
          raw_data: { 'flag' => false, 'nullable' => nil }, tracker_id: 'oracle',
          user_id: import.user_id, import_id: import.id, created_at: Time.current, updated_at: Time.current }
      end
    end
    input = 'batch_failure_input.json'
    write(input.delete_suffix('.json'), batches)
    writer = BatchWriter.new(import, atomic)
    failure = nil
    begin
      if atomic
        ActiveRecord::Base.transaction { batches.each { |batch| writer.write(batch) } }
      else
        batches.each { |batch| writer.write(batch) }
      end
    rescue ActiveRecord::StatementInvalid => e
      failure = { 'class' => e.class.name, 'message' => e.message }
    end
    snapshot(import).merge('zone' => 'UTC', 'locale' => 'de', 'input' => input, 'error' => failure)
  ensure
    connection = ActiveRecord::Base.connection
    %w[points notifications imports users].each do |table|
      key = table == 'users' ? 'id' : 'user_id'
      connection.execute("DELETE FROM #{table} WHERE #{key}=987001")
    end
  end

  def snapshot(import)
    connection = ActiveRecord::Base.connection
    sql = POINT_COLUMNS.map do |column|
      column == 'lonlat' ? 'ST_AsText(lonlat::geometry) AS lonlat' : connection.quote_column_name(column)
    end.join(',')
    points = connection.select_all("SELECT #{sql} FROM points WHERE import_id=#{import.id} ORDER BY id").to_a
    points.each do |point|
      %w[motion_data raw_data].each { |key| point[key] = JSON.parse(point[key]) if point[key].is_a?(String) }
      %w[inrids in_regions].each { |key| point[key] = Point.type_for_attribute(key).deserialize(point[key]) }
      %w[altitude_decimal course course_accuracy].each { |key| point[key] = point[key]&.to_s }
    end
    sources = connection.select_all(<<~SQL).to_a
      SELECT digest,tracker_id,topic,ssid,bssid,connection,trigger,battery_status,
             array_to_json(inrids) AS inrids,array_to_json(in_regions) AS in_regions
      FROM point_sources WHERE id IN (SELECT source_id FROM points WHERE import_id=#{import.id}) ORDER BY digest
    SQL
    sources.each do |source|
      %w[inrids in_regions].each { |key| source[key] = JSON.parse(source[key]) if source[key].is_a?(String) }
    end
    { 'import' => import.reload.attributes.slice(*IMPORT_COLUMNS), 'points' => points, 'sources' => sources,
      'notifications' => Notification.where(user_id: import.user_id).order(:id).pluck(:title, :content, :kind),
      'jobs' => ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| { 'type' => job[:job].name, 'args' => job[:args] } } }
  end
end
