# frozen_string_literal: true

class PendingImports::CleanupJob < ApplicationJob
  queue_as :low_priority

  def perform
    expired = 0
    claimed = 0

    # Expired and never claimed — purge blob + destroy record
    PendingImport.expired.where(claimed_at: nil).find_each do |pi|
      expired += 1 if purge_unclaimed(pi)
    end

    # Claimed more than 7 days ago — destroy record but keep the blob while
    # the user's Import still references it (shared via blob reassignment).
    # If the Import was deleted in the meantime, this detach removes the last
    # attachment and the blob must be purged here or it leaks forever.
    PendingImport.where('claimed_at < ?', 7.days.ago).find_each do |pi|
      blob = pi.file.blob if pi.file.attached?
      pi.file.detach if pi.file.attached?
      blob.purge_later if blob && blob.attachments.reload.none?
      pi.destroy
      claimed += 1
    end

    Rails.logger.info(
      "PendingImports::CleanupJob: purged #{expired} expired unclaimed, #{claimed} claimed >7d; " \
      "#{PendingImport.where(claimed_at: nil).count} unclaimed remain"
    )
  end

  private

  def purge_unclaimed(pending_import)
    pending_import.with_lock do
      next false if pending_import.claimed_at? || pending_import.expires_at > Time.current
      next pending_import.destroy unless pending_import.file.attached?

      blob = pending_import.file.blob
      blob.delete
      pending_import.file.detach
      blob.destroy!
      pending_import.destroy!
    end
  end
end
