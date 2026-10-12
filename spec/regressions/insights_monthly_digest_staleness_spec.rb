# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights monthly digest staleness', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  context 'when an existing monthly digest is older than the latest stat' do
    let!(:stat) do
      create(:stat, user: user, year: 2026, month: 4, distance: 100_000,
                    daily_distance: { '1' => 50_000, '8' => 50_000 })
    end

    let!(:stale_digest) do
      digest = create(:users_digest, :monthly,
                      user: user, year: 2026, month: 4,
                      monthly_distances: { '1' => 5000 })
      digest.update_columns(updated_at: 2.days.ago, created_at: 2.days.ago)
      digest
    end

    before do
      user.stats.where(year: 2026, month: 4).update_all(updated_at: 1.minute.ago)
    end

    it 'recalculates the monthly digest before rendering' do
      original_updated_at = stale_digest.updated_at

      get details_insights_url(year: '2026', month: '4')

      expect(response.status).to eq(200)
      expect(stale_digest.reload.updated_at).to be > original_updated_at
    end
  end
end
