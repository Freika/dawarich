# frozen_string_literal: true

class Swarm::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    checkins = Swarm::Checkins.parse(load_json_data)

    checkins.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      bulk_insert_points(batch.map { |checkin| build_point(checkin) })
      broadcast_import_progress(import, (batch_index + 1) * BATCH_SIZE)
    end
  end

  private

  def build_point(checkin)
    {
      lonlat: "POINT(#{checkin.longitude} #{checkin.latitude})",
      timestamp: checkin.time.to_i,
      user_id: user_id,
      import_id: import.id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def importer_name
    'Foursquare Swarm'
  end
end
