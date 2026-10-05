# frozen_string_literal: true

class PendingImports::CleanupJob < ApplicationJob
  KEY = 'cron:pending_imports_cleanup'
  queue_as :low_priority

  def perform
    return if JobOwnership.with_owner(KEY) { :owned } == :not_owner

    expired = 0
    claimed = 0

    # Expired and never claimed — purge blob + destroy record
    each_owned(PendingImport.expired.where(claimed_at: nil)) do |pi|
      pi.file.purge if pi.file.attached?
      pi.destroy
      expired += 1
    end

    # Claimed more than 7 days ago — destroy record but keep the blob while
    # the user's Import still references it (shared via blob reassignment).
    # If the Import was deleted in the meantime, this detach removes the last
    # attachment and the blob must be purged here or it leaks forever.
    each_owned(PendingImport.where('claimed_at < ?', 7.days.ago)) do |pi|
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

  def each_owned(scope, &work)
    scope.in_batches(of: 1000) do |batch|
      result = JobOwnership.with_owner(KEY) { batch.each(&work) }
      break if result == :not_owner
    end
  end
end
