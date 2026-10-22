# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::UnlockDeck do
  let(:user) { create(:user) }
  let(:deck) { described_class.new(user) }

  def unlock(key)
    Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: key)
  end

  it 'claims the first card and blocks another tab until it is acknowledged' do
    first = unlock('FR')
    unlock('DE')

    claim = deck.claim

    expect(claim.event).to eq(first)
    expect(claim.remaining).to eq(2)
    expect(deck.claim).to eq(:busy)
    expect(deck.claim(resume_token: claim.event.claim_token).event).to eq(first)
    expect(deck.acknowledge(id: first.id, token: 'wrong')).to be(false)
    expect(deck.acknowledge(id: first.id, token: claim.event.claim_token)).to be(true)
    # A lost response after a successful write must not strand the UI on this card.
    expect(deck.acknowledge(id: first.id, token: claim.event.claim_token)).to be(true)
    expect(deck.claim(batch_end_id: claim.batch_end_id).event.key).to eq('DE')
  end

  it 'reclaims an interrupted card after the short lease' do
    first = unlock('FR')
    claim = deck.claim
    token = claim.event.claim_token
    first.update!(claimed_at: 1.minute.ago)

    retry_claim = deck.claim

    expect(retry_claim.event).to eq(first)
    expect(retry_claim.event.claim_token).not_to eq(token)
    expect(deck.acknowledge(id: first.id, token: token)).to be(false)
  end

  it 'dismisses only the original batch, preserving later unlocks' do
    unlock('FR')
    claim = deck.claim
    unlock('DE')

    deck.dismiss_through(batch_end_id: claim.batch_end_id)

    expect(user.achievement_unlock_events.pending.pluck(:key)).to eq(['DE'])
  end
end
