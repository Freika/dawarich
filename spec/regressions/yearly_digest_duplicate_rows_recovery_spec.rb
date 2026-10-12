# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Yearly digest recalculation with duplicate digest rows' do
  let(:user) { create(:user) }
  let(:year) { 2024 }

  let!(:stat) do
    create(:stat, user: user, year: year, month: 1, distance: 1_000, toponyms: [
             { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'stayed_for' => 480 }] }
           ])
  end

  def recalculate_year
    Users::Digests::CalculateYear.new(user.id, year).call
  end

  def insert_duplicate_yearly_digest
    Users::Digest.insert_all([
                               {
                                 user_id: user.id,
                                 year: year,
                                 month: nil,
                                 period_type: Users::Digest.period_types[:yearly],
                                 sharing_uuid: SecureRandom.uuid,
                                 created_at: Time.current,
                                 updated_at: Time.current
                               }
                             ])
  end

  context 'when duplicate yearly digest rows exist for the same user and year' do
    before do
      recalculate_year
      insert_duplicate_yearly_digest
    end

    it 'does not raise a validation error' do
      expect { recalculate_year }.not_to raise_error
    end

    it 'collapses the duplicates into a single yearly digest' do
      recalculate_year

      expect(user.digests.yearly.where(year: year).count).to eq(1)
    end

    it 'keeps the digest updatable with fresh data' do
      stat.update!(distance: 2_000)

      digest = recalculate_year

      expect(digest.distance).to eq(2_000)
    end
  end

  context 'when recalculating repeatedly without duplicates' do
    it 'remains idempotent and keeps a single row' do
      recalculate_year
      recalculate_year

      expect(user.digests.yearly.where(year: year).count).to eq(1)
    end
  end
end
