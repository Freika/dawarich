# frozen_string_literal: true

module PendingImportClaimable
  extend ActiveSupport::Concern

  private

  def claim_pending_import_for(user)
    ticket = session.delete(:pending_import_ticket)
    return if ticket.blank?

    pending = PendingImport.claimable.find_by(claim_ticket: ticket)
    unless pending
      flash[:alert] = I18n.t('controllers.concerns.pending_import_claimable.expired')
      return
    end

    case attempt_claim(pending, user)
    when :claimed
      flash[:notice] = I18n.t(
        'controllers.concerns.pending_import_claimable.importing',
        filename: pending.original_filename
      )
    when :already_claimed
      flash[:alert] = I18n.t('controllers.concerns.pending_import_claimable.expired')
    else
      flash[:alert] = I18n.t('controllers.concerns.pending_import_claimable.queue_failed')
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
