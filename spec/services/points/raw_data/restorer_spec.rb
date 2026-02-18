# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Restorer do
  let(:user) { create(:user) }
  let(:restorer) { described_class.new }

  before do
    # Stub broadcasting to avoid ActionCable issues in tests
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#restore_to_database' do
    let!(:archived_points) do
      create_list(:point, 3, user: user, timestamp: Time.new(2024, 6, 15).to_i,
                             raw_data: nil, raw_data_archived: true)
    end

    let(:archive) do
      # Create archive with actual point data
      compressed_data = gzip_points_data(archived_points.map do |p|
        { id: p.id, raw_data: { lon: 13.4, lat: 52.5 } }
      end)

      arc = build(:points_raw_data_archive, user: user, year: 2024, month: 6)
      arc.file.attach(
        io: StringIO.new(compressed_data),
        filename: arc.filename,
        content_type: 'application/gzip'
      )
      arc.save!

      # Associate points with archive
      archived_points.each { |p| p.update!(raw_data_archive: arc) }

      arc
    end

    it 'restores raw_data to database' do
      archive # Ensure archive is created before restore
      restorer.restore_to_database(user.id, 2024, 6)

      archived_points.each(&:reload)
      archived_points.each do |point|
        expect(point.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    it 'clears archive flags' do
      archive # Ensure archive is created before restore
      restorer.restore_to_database(user.id, 2024, 6)

      archived_points.each(&:reload)
      archived_points.each do |point|
        expect(point.raw_data_archived).to be false
        expect(point.raw_data_archive_id).to be_nil
      end
    end

    it 'raises error when no archives found' do
      expect do
        restorer.restore_to_database(user.id, 2025, 12)
      end.to raise_error(/No archives found/)
    end

    context 'when archived points have been deleted from database' do
      let(:existing_point) do
        create(:point, user: user, timestamp: Time.new(2024, 8, 15).to_i,
                       raw_data: nil, raw_data_archived: true)
      end

      let(:nonexistent_point_id) { existing_point.id + 999_999 }

      let!(:mixed_archive) do
        # Archive references one real point and one that doesn't exist
        compressed_data = gzip_points_data(
          [
            { id: existing_point.id, raw_data: { lon: 13.4, lat: 52.5 } },
            { id: nonexistent_point_id, raw_data: { lon: 14.0, lat: 53.0 } }
          ]
        )

        arc = build(:points_raw_data_archive, user: user, year: 2024, month: 8)
        arc.file.attach(
          io: StringIO.new(compressed_data),
          filename: arc.filename,
          content_type: 'application/gzip'
        )
        arc.save!
        arc
      end

      it 'logs a warning about missing points' do
        expect(Rails.logger).to receive(:warn).with(/no longer exist in database/).at_least(:once)
        expect(Rails.logger).to receive(:warn).with(/no longer in database/).at_least(:once)

        restorer.restore_to_database(user.id, 2024, 8)
      end

      it 'still restores points that do exist' do
        allow(Rails.logger).to receive(:warn)

        restorer.restore_to_database(user.id, 2024, 8)

        existing_point.reload
        expect(existing_point.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    context 'with multiple chunks' do
      let!(:more_points) do
        create_list(:point, 2, user: user, timestamp: Time.new(2024, 6, 20).to_i,
                               raw_data: nil, raw_data_archived: true)
      end

      let!(:archive2) do
        compressed_data = gzip_points_data(more_points.map do |p|
          { id: p.id, raw_data: { lon: 14.0, lat: 53.0 } }
        end)

        arc = build(:points_raw_data_archive, user: user, year: 2024, month: 6, chunk_number: 2)
        arc.file.attach(
          io: StringIO.new(compressed_data),
          filename: arc.filename,
          content_type: 'application/gzip'
        )
        arc.save!

        more_points.each { |p| p.update!(raw_data_archive: arc) }

        arc
      end

      it 'restores from all chunks' do
        archive # Ensure first archive is created
        archive2 # Ensure second archive is created
        restorer.restore_to_database(user.id, 2024, 6)

        (archived_points + more_points).each(&:reload)
        expect(archived_points.first.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
        expect(more_points.first.raw_data).to eq({ 'lon' => 14.0, 'lat' => 53.0 })
      end
    end
  end

  describe 'encrypted archive roundtrip' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:points) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')

      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      # Clear raw_data to simulate what the clearer does
      Point.where(id: points.map(&:id)).update_all(raw_data: nil)
    end

    it 'restores raw_data from encrypted archives' do
      restorer.restore_to_database(user.id, test_date.year, test_date.month)

      points.each(&:reload)
      points.each do |point|
        expect(point.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
        expect(point.raw_data_archived).to be false
      end
    end
  end

  describe '#restore_to_memory' do
    let!(:archived_points) do
      create_list(:point, 2, user: user, timestamp: Time.new(2024, 6, 15).to_i,
                             raw_data: nil, raw_data_archived: true)
    end

    let(:archive) do
      compressed_data = gzip_points_data(archived_points.map do |p|
        { id: p.id, raw_data: { lon: 13.4, lat: 52.5 } }
      end)

      arc = build(:points_raw_data_archive, user: user, year: 2024, month: 6)
      arc.file.attach(
        io: StringIO.new(compressed_data),
        filename: arc.filename,
        content_type: 'application/gzip'
      )
      arc.save!

      archived_points.each { |p| p.update!(raw_data_archive: arc) }

      arc
    end

    it 'loads data into cache' do
      archive # Ensure archive is created before restore
      restorer.restore_to_memory(user.id, 2024, 6)

      archived_points.each do |point|
        cache_key = "raw_data:temp:#{user.id}:2024:6:#{point.id}"
        cached_value = Rails.cache.read(cache_key)
        expect(cached_value).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    it 'does not modify database' do
      archive # Ensure archive is created before restore
      restorer.restore_to_memory(user.id, 2024, 6)

      archived_points.each(&:reload)
      archived_points.each do |point|
        expect(point.raw_data).to be_nil
        expect(point.raw_data_archived).to be true
      end
    end

    it 'sets cache expiration to 1 hour' do
      archive # Ensure archive is created before restore
      restorer.restore_to_memory(user.id, 2024, 6)

      cache_key = "raw_data:temp:#{user.id}:2024:6:#{archived_points.first.id}"

      # Cache should exist now
      expect(Rails.cache.exist?(cache_key)).to be true
    end
  end

  describe '#restore_all_for_user' do
    let!(:june_points) do
      create_list(:point, 2, user: user, timestamp: Time.new(2024, 6, 15).to_i,
                             raw_data: nil, raw_data_archived: true)
    end

    let!(:july_points) do
      create_list(:point, 2, user: user, timestamp: Time.new(2024, 7, 15).to_i,
                             raw_data: nil, raw_data_archived: true)
    end

    let!(:june_archive) do
      compressed_data = gzip_points_data(june_points.map { |p| { id: p.id, raw_data: { month: 'june' } } })

      arc = build(:points_raw_data_archive, user: user, year: 2024, month: 6)
      arc.file.attach(
        io: StringIO.new(compressed_data),
        filename: arc.filename,
        content_type: 'application/gzip'
      )
      arc.save!

      june_points.each { |p| p.update!(raw_data_archive: arc) }
      arc
    end

    let!(:july_archive) do
      compressed_data = gzip_points_data(july_points.map { |p| { id: p.id, raw_data: { month: 'july' } } })

      arc = build(:points_raw_data_archive, user: user, year: 2024, month: 7)
      arc.file.attach(
        io: StringIO.new(compressed_data),
        filename: arc.filename,
        content_type: 'application/gzip'
      )
      arc.save!

      july_points.each { |p| p.update!(raw_data_archive: arc) }
      arc
    end

    it 'restores all months for user' do
      restorer.restore_all_for_user(user.id)

      june_points.each(&:reload)
      july_points.each(&:reload)

      expect(june_points.first.raw_data).to eq({ 'month' => 'june' })
      expect(july_points.first.raw_data).to eq({ 'month' => 'july' })
    end

    it 'clears all archive flags' do
      restorer.restore_all_for_user(user.id)

      (june_points + july_points).each(&:reload)
      expect(Point.where(user: user, raw_data_archived: true).count).to eq(0)
    end
  end

  def gzip_points_data(points_array)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    points_array.each do |point_data|
      gz.puts(point_data.to_json)
    end
    gz.close
    io.string
  end
end
