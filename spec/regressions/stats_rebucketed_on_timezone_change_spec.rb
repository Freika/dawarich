# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stats are rebucketed when the user changes timezone' do
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
  let!(:stat) do
    create(:stat, user: user, year: 2025, month: 12,
                  calculation_version: Stats::CalculateMonth::CALCULATION_VERSION)
  end

  it 'marks the stored months stale when the timezone changes' do
    user.settings['timezone'] = 'America/New_York'
    user.save!

    expect(stat.reload.calculation_version).to eq(0)
  end

  it 'leaves them alone when an unrelated setting changes' do
    user.settings['route_opacity'] = 0.5
    user.save!

    expect(stat.reload.calculation_version).to eq(Stats::CalculateMonth::CALCULATION_VERSION)
  end

  it 'leaves them alone when the timezone is written with the same value' do
    user.settings['timezone'] = 'Europe/Berlin'
    user.save!

    expect(stat.reload.calculation_version).to eq(Stats::CalculateMonth::CALCULATION_VERSION)
  end

  it 'covers the web settings form, which writes settings without the updater' do
    expect do
      user.settings['timezone'] = 'Asia/Tokyo'
      user.save
    end.to change { stat.reload.calculation_version }.to(0)
  end

  describe 'ordering against the transaction' do
    it 'marks the months stale inside the transaction' do
      ActiveRecord::Base.transaction do
        user.settings['timezone'] = 'America/New_York'
        user.save!

        expect(stat.reload.calculation_version).to eq(0)
      end
    end

    it 'does not enqueue the rebuild until the timezone write has committed' do
      enqueued_inside = nil

      ActiveRecord::Base.transaction do
        user.settings['timezone'] = 'America/New_York'
        user.save!
        enqueued_inside = enqueued_jobs.count { |job| job[:job] == Stats::CalculatingJob }
      end

      expect(enqueued_inside).to eq(0)
      expect(enqueued_jobs.count { |job| job[:job] == Stats::CalculatingJob }).to eq(1)
    end
  end
end
