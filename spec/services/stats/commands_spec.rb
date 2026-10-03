# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::Commands do
  let(:user) { create(:user) }
  let(:at) { Time.zone.parse('2026-03-29 12:34:56 UTC') }
  let(:month) { { 'user_id' => user.id, 'year' => 2024, 'month' => 3, 'notify_on_failure' => false } }

  def handle(kind, payload) = described_class::HANDLERS.fetch(kind).fetch(:call).call(payload)

  it 'stats.calculate_month enqueues the month at run_at with its notification flag' do
    expect { handle('stats.calculate_month', month.merge('run_at' => at.to_i)) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 3, notify_on_failure: false).at(at)
  end

  it 'stats.calculate_month does nothing for a missing user' do
    expect { handle('stats.calculate_month', month.merge('user_id' => 0, 'run_at' => at.to_i)) }
      .not_to have_enqueued_job(Stats::CalculatingJob)
  end

  it 'stats.caches_invalidated deletes the toponym caches, or every user cache for scope all' do
    allow(Rails.cache).to receive(:delete).and_call_original
    handle('stats.caches_invalidated', { 'user_id' => user.id, 'year' => 2024, 'scope' => 'toponyms' })
    expect(Rails.cache).to have_received(:delete).with("dawarich/user_#{user.id}_countries_visited")
    expect(Rails.cache).not_to have_received(:delete).with("dawarich/user_#{user.id}_total_distance")

    handle('stats.caches_invalidated', { 'user_id' => user.id, 'year' => 2024, 'scope' => 'all' })
    expect(Rails.cache).to have_received(:delete).with("dawarich/user_#{user.id}_total_distance")
  end
end
