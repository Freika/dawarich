# frozen_string_literal: true

module Achievements
  class UnlocksController < ApplicationController
    before_action :authenticate_user!

    def next
      return head :no_content unless UnlockEvent.pending.exists?(user_id: current_user.id)

      state = Progress.find_by(user: current_user, achievement_key: Progress::EXPLORATION_KEY)&.state || {}
      10.times do
        claim = deck.claim(resume_token: params[:claim_token].to_s, batch_end_id: positive_id(params[:batch_end_id]))
        return render json: { retry_after: 2 }, status: :conflict if claim == :busy
        return head :no_content unless claim

        card = UnlockCardPresenter.new(event: claim.event, state: state,
                                       timezone: current_user.safe_settings.timezone).call
        if card
          return render json: {
            id: claim.event.id,
            token: claim.event.claim_token,
            batch_end_id: claim.batch_end_id,
            remaining: claim.remaining,
            html: render_to_string(partial: 'achievements/unlock_reveal', formats: [:html],
                                   locals: { card: card, count: claim.remaining })
          }
        end

        deck.acknowledge(id: claim.event.id, token: claim.event.claim_token)
      end
      head :no_content
    end

    def seen
      return head :bad_request unless positive_id(params[:id]) && params[:claim_token].present?

      deck.acknowledge(id: params[:id], token: params[:claim_token]) ? head(:no_content) : head(:conflict)
    end

    def dismiss
      return head :bad_request unless positive_id(params[:batch_end_id])

      deck.dismiss_through(batch_end_id: params[:batch_end_id])
      head :no_content
    end

    private

    def deck
      @deck ||= UnlockDeck.new(current_user)
    end

    def positive_id(value)
      return unless value.to_s.match?(/\A[1-9]\d{0,18}\z/)

      number = value.to_i
      number if number <= (2**63) - 1
    end
  end
end
