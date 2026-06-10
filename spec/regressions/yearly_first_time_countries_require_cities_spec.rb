# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Yearly first-time visits ignore countries without qualifying cities' do
  let(:user) { create(:user) }

  let!(:previous_year_stat) do
    create(:stat, user: user, year: 2025, month: 6, distance: 100, toponyms: [
             { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'stayed_for' => 480 }] }
           ])
  end

  let!(:current_year_stat) do
    create(:stat, user: user, year: 2026, month: 4, distance: 100, toponyms: [
             { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'stayed_for' => 480 }] },
             { 'country' => 'France', 'cities' => [] }
           ])
  end

  def yearly_first_time_countries
    Users::Digests::FirstTimeVisitsCalculator.new(user, 2026).call['countries']
  end

  def monthly_first_time_countries
    Users::Digests::MonthlyFirstTimeVisitsCalculator.new(user, 2026, 4).call['countries']
  end

  it 'does not report a country whose cities array is empty' do
    expect(yearly_first_time_countries).to be_empty
  end

  it 'agrees with the monthly calculator on the same data' do
    expect(yearly_first_time_countries).to eq(monthly_first_time_countries)
  end

  it 'still reports genuinely new countries with qualifying cities' do
    current_year_stat.update!(toponyms: current_year_stat.toponyms + [
      { 'country' => 'Spain', 'cities' => [{ 'city' => 'Madrid', 'stayed_for' => 300 }] }
    ])

    expect(yearly_first_time_countries).to eq(['Spain'])
  end
end
