# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::MonthSummary do
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

  describe '#call' do
    subject(:summary) { described_class.new(user: user, month: '2026-04').call }

    it "returns the month key as 'YYYY-MM'" do
      expect(summary[:month]).to eq('2026-04')
    end

    it "returns the user's timezone" do
      expect(summary[:tz]).to eq('Europe/Berlin')
    end

    it 'returns weeks as 6 rows of 7 cells each' do
      expect(summary[:weeks].length).to eq(6)
      summary[:weeks].each { |week| expect(week.length).to eq(7) }
    end

    it 'fills padding days from adjacent months with in_month: false' do
      flat = summary[:weeks].flatten
      out_of_month = flat.reject { |cell| cell[:in_month] }
      expect(out_of_month).not_to be_empty
      out_of_month.each do |cell|
        expect(cell[:date]).to be_present
        expect(cell[:in_month]).to eq(false)
      end
    end

    it 'starts weeks on Monday' do
      first_cell = summary[:weeks].first.first
      expect(Date.parse(first_cell[:date]).wday).to eq(1) # Monday
    end

    context 'with visits and tracks' do
      let(:place) { create(:place, :with_geodata) }

      before do
        # One visit on April 22, 2026: 90 minutes (visits.duration is MINUTES)
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: Time.zone.parse('2026-04-22 10:00:00 +0200'),
               ended_at: Time.zone.parse('2026-04-22 11:30:00 +0200'),
               duration: 90,
               status: 'confirmed')

        # One track on April 22, 2026: 3600 seconds (tracks.duration is SECONDS)
        create(:track,
               user: user,
               start_at: Time.zone.parse('2026-04-22 12:00:00 +0200'),
               end_at: Time.zone.parse('2026-04-22 13:00:00 +0200'),
               duration: 3600)
      end

      it 'counts visits on the day' do
        day = summary[:days]['2026-04-22']
        expect(day[:visit_count]).to eq(1)
      end

      it 'counts confirmed visits' do
        day = summary[:days]['2026-04-22']
        expect(day[:confirmed_count]).to eq(1)
      end

      it 'combines visits (minutes to seconds) and tracks (seconds) into tracked_seconds' do
        day = summary[:days]['2026-04-22']
        # 90 minutes * 60 + 3600 seconds = 5400 + 3600 = 9000
        expect(day[:tracked_seconds]).to eq(9000)
      end
    end

    context 'with suggested visits' do
      let(:place) { create(:place, :with_geodata) }

      before do
        create(:visit,
               user: user,
               place: place,
               started_at: Time.zone.parse('2026-04-10 09:00:00 +0200'),
               ended_at: Time.zone.parse('2026-04-10 10:00:00 +0200'),
               duration: 60,
               status: 'suggested')
      end

      it 'flags days with suggested_count > 0' do
        day = summary[:days]['2026-04-10']
        expect(day[:suggested_count]).to eq(1)
      end
    end

    context 'when a visit straddles local midnight' do
      let(:place) { create(:place, :with_geodata) }

      before do
        # 23:30 UTC on April 22 is 01:30 April 23 in Europe/Berlin (CEST +02:00)
        create(:visit,
               user: user,
               place: place,
               started_at: Time.zone.parse('2026-04-22 23:30:00 UTC'),
               ended_at: Time.zone.parse('2026-04-23 00:30:00 UTC'),
               duration: 60,
               status: 'confirmed')
      end

      it 'groups by the user timezone, not UTC' do
        expect(summary[:days]).to have_key('2026-04-23')
        expect(summary[:days]['2026-04-23'][:visit_count]).to eq(1)
        expect(summary[:days]['2026-04-22']).to be_nil
      end
    end
  end

  describe 'Lite plan restrictions' do
    let(:lite_user) { create(:user, :lite_plan, settings: { 'timezone' => 'UTC' }) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    it 'marks cells outside the 12-month window as disabled' do
      summary = described_class.new(user: lite_user, month: 18.months.ago.strftime('%Y-%m')).call
      in_month_cells = summary[:weeks].flatten.select { |c| c[:in_month] }
      expect(in_month_cells).to all(include(disabled: true))
    end

    it 'does not mark current-month cells as disabled' do
      summary = described_class.new(user: lite_user, month: Date.current.strftime('%Y-%m')).call
      in_month_cells = summary[:weeks].flatten.select { |c| c[:in_month] }
      expect(in_month_cells).to all(include(disabled: false))
    end
  end

  describe '.heat_bucket' do
    it 'returns 0 for 0 tracked seconds' do
      expect(described_class.heat_bucket(0)).to eq(0)
    end

    it 'returns 1 for under 2 hours' do
      expect(described_class.heat_bucket(3600)).to eq(1)
    end

    it 'returns 2 for 2 to 4 hours' do
      expect(described_class.heat_bucket(3 * 3600)).to eq(2)
    end

    it 'returns 3 for 4 to 8 hours' do
      expect(described_class.heat_bucket(6 * 3600)).to eq(3)
    end

    it 'returns 4 for 8 to 12 hours' do
      expect(described_class.heat_bucket(10 * 3600)).to eq(4)
    end

    it 'returns 5 for 12 or more hours' do
      expect(described_class.heat_bucket(13 * 3600)).to eq(5)
    end
  end

  describe '.cache_key_for' do
    it 'returns a deterministic key for the same user and month' do
      key1 = described_class.cache_key_for(user, Date.parse('2026-04-15'))
      key2 = described_class.cache_key_for(user, Date.parse('2026-04-01'))
      expect(key1).to eq(key2)
    end

    it 'accepts a string month' do
      key1 = described_class.cache_key_for(user, '2026-04')
      key2 = described_class.cache_key_for(user, Date.parse('2026-04-10'))
      expect(key1).to eq(key2)
    end

    it 'returns a different key for different months' do
      key1 = described_class.cache_key_for(user, Date.parse('2026-04-15'))
      key2 = described_class.cache_key_for(user, Date.parse('2026-05-15'))
      expect(key1).not_to eq(key2)
    end

    it 'returns a different key for different users' do
      other = create(:user)
      key1 = described_class.cache_key_for(user, '2026-04')
      key2 = described_class.cache_key_for(other, '2026-04')
      expect(key1).not_to eq(key2)
    end
  end

  describe 'caching' do
    let(:place) { create(:place, :with_geodata) }

    before do
      create(:visit,
             user: user,
             place: place,
             started_at: Time.zone.parse('2026-04-10 09:00:00 +0200'),
             ended_at: Time.zone.parse('2026-04-10 10:00:00 +0200'),
             duration: 60,
             status: 'confirmed')
      allow(Rails.cache).to receive(:fetch).and_call_original
    end

    it 'caches the result so a second call skips the database' do
      described_class.new(user: user, month: '2026-04').call

      queries = []
      counter = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql] }

      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        described_class.new(user: user, month: '2026-04').call
      end

      user_queries = queries.reject { |q| q =~ /SCHEMA|TRANSACTION|BEGIN|COMMIT|SAVEPOINT/ }
      expect(user_queries).to be_empty
    end
  end
end
