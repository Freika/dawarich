# frozen_string_literal: true

class Imports::Download
  CLIENT_WRAPPED_KEY = 'dawarich_client_wrapped'
  ORIGINAL_FILENAME_KEY = 'dawarich_original_filename'
  SOURCE_BLOB_KEY = 'dawarich_download_source_blob_id'

  def initialize(import)
    @import = import
  end

  def ready?
    return false unless import.file.attached?

    return true unless wrapped_candidate?
    return false unless import.prepared_download.attached?

    prepared = import.prepared_download.blob
    prepared.id == source.id || prepared.metadata[SOURCE_BLOB_KEY] == source.id
  end

  def url
    return unless import.file.attached?

    return original_url unless wrapped_candidate? && import.prepared_download.attached?
    return original_url if import.prepared_download.blob_id == source.id

    import.prepared_download.url(filename: extracted_filename, disposition: :attachment)
  end

  def original_url
    return unless import.file.attached?

    filename = import.name
    filename = "#{filename}.zip" if wrapped_candidate? && !filename.end_with?('.zip')
    import.file.url(filename: filename, disposition: :attachment)
  end

  def prepare
    import.with_source_file_lock do
      import.reload
      @source = nil
      return unless import.file.attached?

      prepare_file
    end
  end

  def unwrapped_name
    return unless wrapped_candidate? && original_filename

    name = extracted_filename
    name unless name == import.name
  end

  private

  def prepare_file
    return if ready?

    archive_path = Imports::SecureFileDownloader.new(import.file).download_to_temp_file
    archive = Archive::Unzipper.inspect_archive(archive_path)
    return attach_original unless archive.kind == :single_entry && same_filename?(archive.entry_name)

    extracted_path = Archive::Unzipper.extract_single(archive_path)
    prepared = nil
    File.open(extracted_path, 'rb') do |file|
      prepared = ActiveStorage::Blob.create_after_unfurling!(
        io: file, filename: original_filename,
        content_type: Marcel::MimeType.for(Pathname.new(extracted_path), name: original_filename),
        metadata: { SOURCE_BLOB_KEY => source.id }
      )
      prepared.upload_without_unfurling(file)
      import.prepared_download.attach(prepared)
    end
  rescue Archive::Unzipper::ArchiveTooLarge
    attach_original
  rescue StandardError
    prepared&.purge_later if prepared && !prepared.attachments.exists?
    raise
  ensure
    File.unlink(extracted_path) if extracted_path && File.exist?(extracted_path)
    File.unlink(archive_path) if archive_path && File.exist?(archive_path)
  end

  attr_reader :import

  def source
    @source ||= import.file.blob
  end

  def wrapped_candidate?
    return false unless source

    return source.metadata[CLIENT_WRAPPED_KEY] if source.metadata.key?(CLIENT_WRAPPED_KEY)

    legacy_filename.present?
  end

  def original_filename
    source.metadata[ORIGINAL_FILENAME_KEY] || legacy_filename
  end

  def legacy_filename
    filename = source.filename.to_s
    return unless filename.end_with?('.zip')

    inner = filename.delete_suffix('.zip')
    inner if Imports::ZipExtractor::SUPPORTED_EXTENSIONS.include?(File.extname(inner).downcase)
  end

  def same_filename?(entry_name)
    ActiveStorage::Filename.new(entry_name.dup.force_encoding(Encoding::UTF_8)).to_s == original_filename
  end

  def attach_original
    import.prepared_download.attach(source)
  end

  def extracted_filename
    original = original_filename
    return original if import.name == source.filename.to_s

    suffix = import.name.delete_prefix(original.to_s)
    if original && suffix.match?(/\A_\d{8}_\d{6}\.zip\z/)
      extension = File.extname(original)
      return "#{original.delete_suffix(extension)}#{suffix.delete_suffix('.zip')}#{extension}"
    end

    import.name
  end
end
