# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatsHelper, type: :helper do
  describe 'rendering /stats for a year that contains a reset month' do
    let(:user) { create(:user) }

    before do
      create(:stat, user: user, year: 2025, month: 1, toponyms: [
               { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
             ])

      reset_stat = build(:stat, user: user, year: 2025, month: 2, toponyms: nil)
      reset_stat.save!(validate: false)
      reset_stat.update_columns(toponyms: nil)
    end

    let(:year_stats) { Stat.where(user: user, year: 2025).order(:month) }

    it 'returns [] from Stat#toponyms when the column is nil' do
      reset_stat = year_stats.find_by(month: 2)
      expect(reset_stat.read_attribute(:toponyms)).to be_nil
      expect(reset_stat.toponyms).to eq([])
    end

    it 'does not raise when computing countries_and_cities_stat_for_year' do
      expect do
        helper.countries_and_cities_stat_for_year(2025, year_stats)
      end.not_to raise_error
    end

    it 'still counts countries from months that have data' do
      result = helper.countries_and_cities_stat_for_year(2025, year_stats)

      expect(result[:countries_count]).to eq(1)
      expect(result[:cities_count]).to eq(1)
    end
  end

  describe 'Stats::CalculateMonth#reset_month_stats' do
    let(:user) { create(:user) }

    it 'writes an empty array to toponyms instead of nil' do
      stat = create(:stat, user: user, year: 2025, month: 3, toponyms: [
                      { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
                    ])

      Stats::CalculateMonth.new(user.id, 2025, 3).call

      expect(stat.reload.read_attribute(:toponyms)).to eq([])
    end
  end
end
