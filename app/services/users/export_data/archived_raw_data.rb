# frozen_string_literal: true

# Raw data cleared by the archival pipeline survives only in archive files keyed
# by this instance's point IDs, which an import cannot relink to the new points.
# The export inlines it so every exported point carries its raw_data.
class Users::ExportData::ArchivedRawData
  # ponytail: an archive spanning several 10k-point export batches is downloaded
  # once per batch; cache across batches if large exports get slow.
  #
  # @param rows [Enumerable<Hash>] export query rows with id, raw_data and raw_data_archive_id
  # @return [Hash{Integer => String}] point id => raw_data JSON for points whose raw_data was cleared
  def self.for(rows)
    cleared = rows.select { |row| row['raw_data_archive_id'] && cleared?(row['raw_data']) }

    cleared.group_by { |row| row['raw_data_archive_id'] }.each_with_object({}) do |(archive_id, archive_rows), found|
      wanted = archive_rows.to_set { |row| row['id'] }

      each_entry(archive_id) do |point_id, raw_data|
        found[point_id] = raw_data.to_json if wanted.include?(point_id)
      end
    end
  end

  def self.cleared?(raw_data)
    Point.type_for_attribute('raw_data').deserialize(raw_data).blank?
  end

  def self.each_entry(archive_id)
    archive = Points::RawDataArchive.find(archive_id)
    content = Points::RawData::Encryption.decrypt_if_needed(archive.file.download, archive)
    gz = Zlib::GzipReader.new(StringIO.new(content))
    gz.each_line do |line|
      data = JSON.parse(line)
      yield data['id'], data['raw_data']
    end
  # Only a lost object is skipped: that data is gone either way. Any other error
  # fails the export, so a user's backup never silently drops raw_data.
  rescue ActiveStorage::FileNotFoundError => e
    ExceptionReporter.call(e, "Raw data archive #{archive_id} is missing from storage")
  ensure
    gz&.close
  end

  private_class_method :cleared?, :each_entry
end
