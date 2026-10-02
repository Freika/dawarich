# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Legacy GPX encoding admission' do
  it 'processes real Windows-1252 GPX through the durable native fallback receipt' do
    phoenix_tables!
    import = create(:import, source: :gpx, skip_background_processing: true)
    bytes = '<?xml version="1.0" encoding="Windows-1252"?><gpx><trk><name>'.b +
            [233].pack('C') + '</name><trkseg><trkpt lat="52" lon="13">' \
            '<time>2026-01-01T10:00:00Z</time></trkpt></trkseg></trk></gpx>'.b
    import.file.attach(io: StringIO.new(bytes), filename: 'legacy-codec.gpx')
    event = SecureRandom.uuid
    payload = { 'event_id' => event, 'import_id' => import.id, 'user_id' => import.user_id,
                'time_zone' => 'Europe/Berlin' }
    job_owner!('command:imports.process_gpx', :oban)
    query = <<~SQL.squish
      INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone,native_fallback)
      VALUES(?,?,?,?,true)
    SQL
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(
                                            [query, event, import.id, import.user_id, 'Europe/Berlin']
                                          ))
    Imports::GpxResume.perform(payload)
    expect(import.reload).to be_completed
    expect(import.points.count).to eq(1)
    expect(import.points.sole.timestamp).to eq(1_767_261_600)
    expect(JobOutbox.where(command_type: 'imports.process_gpx')).to be_empty
  end
end
