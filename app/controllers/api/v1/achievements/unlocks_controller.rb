# frozen_string_literal: true

class Api::V1::Achievements::UnlocksController < ApiController
  def next
    if (params.key?(:batch_end_id) && !positive_id(params[:batch_end_id])) ||
       (params.key?(:claim_token) && !valid_token?(params[:claim_token]))
      return invalid_parameters
    end

    collection = ::Achievements::ApiCollection.new(user: current_api_user, url_helpers: self)
    10.times do
      claim = deck.claim(resume_token: params[:claim_token], batch_end_id: positive_id(params[:batch_end_id]))
      return render json: { retry_after: 2 }, status: :conflict if claim == :busy
      return head :no_content unless claim

      card = collection.unlock(claim.event)
      if card
        return render json: { id: claim.event.id, token: claim.event.claim_token,
                              batch_end_id: claim.batch_end_id, remaining: claim.remaining, card: card }
      end
      deck.acknowledge(id: claim.event.id, token: claim.event.claim_token)
    end
    head :no_content
  end

  def seen
    return invalid_parameters unless positive_id(params[:id]) && valid_token?(params[:claim_token])

    deck.acknowledge(id: params[:id], token: params[:claim_token]) ? head(:no_content) : head(:conflict)
  end

  def dismiss
    return invalid_parameters unless positive_id(params[:batch_end_id])

    deck.dismiss_through(batch_end_id: params[:batch_end_id])
    head :no_content
  end

  private

  def deck
    @deck ||= ::Achievements::UnlockDeck.new(current_api_user)
  end

  def invalid_parameters
    render json: { error: 'invalid_parameters' }, status: :unprocessable_content
  end

  def valid_token?(value)
    value.is_a?(String) && value.match?(/\A[0-9a-f]{32}\z/)
  end

  def positive_id(value)
    return unless value.to_s.match?(/\A[1-9]\d{0,18}\z/)

    value.to_i if value.to_i <= (2**63) - 1
  end
end
