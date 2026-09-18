# frozen_string_literal: true

module Achievements
  # Reserves one card at a time. The short lease prevents two open tabs from
  # revealing the same card; an interrupted reveal can be resumed or retried.
  class UnlockDeck
    LEASE = 45.seconds
    Claim = Data.define(:event, :remaining, :batch_end_id)

    def initialize(user)
      @user = user
    end

    def claim(resume_token: nil, batch_end_id: nil)
      @user.with_lock do
        active = events.pending.where(claimed_at: LEASE.ago..).order(:id).first
        return :busy if active && active.claim_token != resume_token

        if active
          active.update!(claimed_at: Time.current)
          return Claim.new(event: active, remaining: pending_through(batch_end_id).count,
                           batch_end_id: batch_end_id || events.pending.maximum(:id))
        end

        batch_end_id ||= events.pending.maximum(:id)
        return nil unless batch_end_id

        available = pending_through(batch_end_id)
        event = available.order(:id).first
        return nil unless event

        event.update!(claimed_at: Time.current, claim_token: SecureRandom.hex(16))
        Claim.new(event: event, remaining: available.count, batch_end_id: batch_end_id)
      end
    end

    def acknowledge(id:, token:)
      return false if token.blank?

      updated = events.pending.where(id: id, claim_token: token)
                      .update_all(seen_at: Time.current, claimed_at: nil, claim_token: nil)
      updated == 1 || events.where(id: id).where.not(seen_at: nil).exists?
    end

    def dismiss_through(batch_end_id:)
      return if batch_end_id.to_i <= 0

      events.pending.where(id: 0..batch_end_id.to_i)
            .update_all(seen_at: Time.current, claimed_at: nil, claim_token: nil)
    end

    private

    def events
      UnlockEvent.where(user_id: @user.id)
    end

    def pending_through(batch_end_id)
      pending = events.pending
      batch_end_id ? pending.where(id: 0..batch_end_id.to_i) : pending
    end
  end
end
