# frozen_string_literal: true

module PendingImportClaimable
  extend ActiveSupport::Concern

  EXPIRED_MESSAGE =
    'Your import link has expired or already been used. You can re-upload from your dashboard.'

  private

  def claim_pending_import_for(user)
    ticket = session.delete(:pending_import_ticket)
    return if ticket.blank?

    pending = PendingImport.claimable.find_by(claim_ticket: ticket)
    unless pending
      flash[:alert] = EXPIRED_MESSAGE
      return
    end

    case attempt_claim(pending, user)
    when :claimed
      flash[:notice] = "Importing #{pending.original_filename}... You'll see it in your dashboard shortly."
    when :already_claimed
      flash[:alert] = EXPIRED_MESSAGE
    else
      flash[:alert] = "Your import couldn't be queued. Please upload the file from your dashboard."
    end
  end

  # A claim failure must never break the sign-up/sign-in it rides on.
  def attempt_claim(pending, user)
    PendingImports::Claim.new(pending, user).call ? :claimed : :already_claimed
  rescue StandardError => e
    Rails.logger.error("Pending import claim failed: #{e.class}: #{e.message}")
    ExceptionReporter.call(e) if defined?(ExceptionReporter)
    :error
  end
end
