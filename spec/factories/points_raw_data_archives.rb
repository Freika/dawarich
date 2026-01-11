# frozen_string_literal: true

FactoryBot.define do
  factory :points_raw_data_archive, class: 'Points::RawDataArchive' do
    user
    year { 2024 }
    month { 6 }
    chunk_number { 1 }
    point_count { 100 }
    point_ids_checksum { Digest::SHA256.hexdigest('1,2,3') }
    archived_at { Time.current }
    metadata do
      {
        format_version: 1,
        compression: 'gzip',
        expected_count: point_count,
        actual_count: point_count
      }
    end

    after(:build) do |archive|
      # Attach a test file
      archive.file.attach(
        io: StringIO.new(gzip_test_data),
        filename: archive.filename,
        content_type: 'application/gzip'
      )
    end
  end
end

def gzip_test_data
  io = StringIO.new
  gz = Zlib::GzipWriter.new(io)
  gz.puts({ id: 1, raw_data: { lon: 13.4, lat: 52.5 } }.to_json)
  gz.puts({ id: 2, raw_data: { lon: 13.5, lat: 52.6 } }.to_json)
  gz.close
  io.string
end
