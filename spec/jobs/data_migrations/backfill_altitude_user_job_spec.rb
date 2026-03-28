# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillAltitudeUserJob do
  describe '#perform' do
    let(:user) { create(:user) }

    context 'with non-archived points' do
      context 'with OwnTracks raw_data containing fractional altitude' do
        let!(:point) do
          create(:point, user: user, altitude: 36,
                         raw_data: { 'alt' => 36.7, 'lat' => 52.225, 'lon' => 13.332 })
        end

        it 'updates altitude to precise value from raw_data' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(36.7)
        end
      end

      context 'with GPX raw_data containing fractional ele' do
        let!(:point) do
          create(:point, user: user, altitude: 719,
                         raw_data: { 'lat' => '47.123', 'lon' => '11.456', 'ele' => '719.2' })
        end

        it 'updates altitude to precise value from ele' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(719.2)
        end
      end

      context 'with Google Phone Takeout raw_data' do
        let!(:point) do
          create(:point, user: user, altitude: 90,
                         raw_data: { 'altitudeMeters' => 90.7, 'accuracyMeters' => 13 })
        end

        it 'updates altitude from altitudeMeters' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(90.7)
        end
      end

      context 'with Overland/GeoJSON properties altitude' do
        let!(:point) do
          create(:point, user: user, altitude: 17,
                         raw_data: {
                           'type' => 'Feature',
                           'geometry' => { 'coordinates' => [-122.03, 37.33, 17.634] },
                           'properties' => { 'altitude' => 17.634 }
                         })
        end

        it 'updates altitude from properties' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(17.63)
        end
      end

      context 'when raw_data altitude matches stored altitude' do
        let!(:point) do
          create(:point, user: user, altitude: 36,
                         raw_data: { 'alt' => 36, 'lat' => 52.225, 'lon' => 13.332 })
        end

        it 'does not issue an update' do
          expect { described_class.new.perform(user.id) }.not_to(change { point.reload.updated_at })
        end
      end

      context 'with empty raw_data' do
        let!(:point) { create(:point, user: user, altitude: 100, raw_data: {}) }

        it 'skips points with empty raw_data' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(100.0)
        end
      end

      context 'with raw_data that has no altitude' do
        let!(:point) do
          create(:point, user: user, altitude: 100,
                         raw_data: { 'latitudeE7' => 533_690_550, 'longitudeE7' => 836_950_010 })
        end

        it 'skips points when no altitude in raw_data' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(100.0)
        end
      end

      context 'with nil altitude on point' do
        let!(:point) do
          create(:point, user: user, altitude: nil,
                         raw_data: { 'alt' => 42.5 })
        end

        it 'fills in altitude from raw_data' do
          described_class.new.perform(user.id)

          expect(point.reload.altitude.to_f).to eq(42.5)
        end
      end
    end

    context 'with archived points' do
      let!(:point) do
        create(:point, user: user, altitude: 719,
                       raw_data: {},
                       raw_data_archived: true)
      end

      let!(:archive) do
        archived_line = { 'id' => point.id, 'raw_data' => { 'ele' => '719.2', 'lat' => '47.0', 'lon' => '11.0' } }
        compressed = compress_jsonl([archived_line])
        encrypted = Points::RawData::Encryption.encrypt(compressed)

        archive = Points::RawDataArchive.create!(
          user_id: user.id,
          year: Time.current.year,
          month: Time.current.month,
          chunk_number: 1,
          point_count: 1,
          point_ids_checksum: Digest::SHA256.hexdigest(point.id.to_s),
          archived_at: Time.current,
          metadata: { 'format_version' => 2, 'expected_count' => 1, 'actual_count' => 1 }
        )

        archive.file.attach(
          io: StringIO.new(encrypted),
          filename: '001.jsonl.gz.enc',
          content_type: 'application/octet-stream'
        )

        point.update_columns(raw_data_archive_id: archive.id)

        archive
      end

      it 'extracts altitude from archived raw_data' do
        described_class.new.perform(user.id)

        expect(point.reload.altitude.to_f).to eq(719.2)
      end
    end

    context 'does not touch other users' do
      let(:other_user) { create(:user) }

      let!(:own_point) do
        create(:point, user: user, altitude: 100,
                       raw_data: { 'alt' => 100.5 })
      end

      let!(:other_point) do
        create(:point, user: other_user, altitude: 200,
                       raw_data: { 'alt' => 200.5 })
      end

      it 'only updates the target user' do
        described_class.new.perform(user.id)

        expect(own_point.reload.altitude.to_f).to eq(100.5)
        expect(other_point.reload.altitude.to_f).to eq(200.0)
      end
    end

    context 'batching' do
      let!(:points) do
        3.times.map do |i|
          create(:point, user: user, altitude: 100 + i,
                         raw_data: { 'alt' => 100.5 + i })
        end
      end

      it 'processes all points across batches' do
        described_class.new.perform(user.id, batch_size: 2)

        points.each_with_index do |point, i|
          expect(point.reload.altitude.to_f).to eq(100.5 + i)
        end
      end
    end
  end

  private

  def compress_jsonl(entries)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    entries.each { |entry| gz.puts(entry.to_json) }
    gz.close
    io.string
  end
end
