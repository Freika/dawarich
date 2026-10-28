# frozen_string_literal: true

class Imports::DeleteSourceFile
  def initialize(import)
    @import = import
  end

  def call
    @import.with_source_file_lock(timeout_seconds: 0) do
      @import.reload
      return :already_deleted unless @import.file.attached? || @import.prepared_download.attached?
      return :unavailable unless @import.source_file_removable?

      @import.transaction do
        blobs = [@import.file.blob, @import.prepared_download.blob].compact.uniq
        @import.file.detach
        @import.prepared_download.detach

        # Detach both references first: the prepared download can be the source
        # blob itself. Active Storage keeps blobs still attached elsewhere via
        # its foreign key constraint, and purges storage outside this request.
        ActiveRecord.after_all_transactions_commit { blobs.each(&:purge_later) }
      end
      :deleted
    end
  rescue WithAdvisoryLock::FailedToAcquireLock
    :unavailable
  end
end
