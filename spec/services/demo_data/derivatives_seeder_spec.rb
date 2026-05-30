# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DemoData::DerivativesSeeder do
  let(:user) { create(:user) }
  let(:anchor) { Time.zone.local(2026, 5, 28).beginning_of_day }
  let(:fixture) do
    Zlib::GzipReader.open(Rails.root.join('lib/assets/demo_derivatives.json.gz')) { |gz| Oj.load(gz.read) }
  end

  describe '#call' do
    before { described_class.new(user, anchor).call }

    it 'creates demo tags for the user' do
      expect(user.tags.demo.count).to be >= 6
    end

    it 'creates demo places scoped to the user with geodata' do
      expect(Place.demo.where(user_id: user.id).count).to be >= 8
      home = Place.demo.find_by(user_id: user.id, name: 'Home')
      expect(home.geodata).to be_present
    end

    it 'creates demo visits scoped to the user' do
      expect(user.visits.demo.count).to be >= 50
    end

    it 'creates the demo Prague trip' do
      expect(user.trips.demo.find_by(name: 'Weekend in Prague')).to be_present
    end

    it 'attaches alternates as PlaceVisit rows on suggested visits' do
      suggested = user.visits.where(status: :suggested).first
      expect(suggested.suggested_places.count).to be >= 1
    end

    it 'creates one Stat per (year, month) bucket derived from stats_daily' do
      expected_months = fixture['stats_daily'].map do |row|
        date = anchor.to_date + row['day_offset'].to_i
        [date.year, date.month]
      end.uniq.to_set
      expect(user.stats.pluck(:year, :month).to_set).to eq(expected_months)
    end

    it 'distributes daily_distance into per-month buckets that sum to the stat distance' do
      user.stats.find_each do |stat|
        sum = stat.daily_distance.sum { |_, d| d }
        expect(stat.distance).to eq(sum)
      end
    end

    it 'marks May (with the Prague weekend) as Berlin+Prague' do
      may_stat = user.stats.find_by(year: 2026, month: 5)
      expect(may_stat.toponyms['cities']).to include('Prague')
      expect(may_stat.toponyms['countries']).to include('Czech Republic')
    end

    it 'marks April (Berlin-only) without Prague toponyms' do
      apr_stat = user.stats.find_by(year: 2026, month: 4)
      expect(apr_stat.toponyms['cities']).not_to include('Prague')
    end
  end

  describe 'Stat anchor shift' do
    let(:fresh_user) { create(:user) }
    let(:shifted_anchor) { Time.zone.local(2027, 1, 15).beginning_of_day }

    it 'buckets stats by calendar months derived from anchor + day_offset' do
      described_class.new(fresh_user, shifted_anchor).call

      expected_months = fixture['stats_daily'].map do |row|
        date = shifted_anchor.to_date + row['day_offset'].to_i
        [date.year, date.month]
      end.uniq.to_set

      expect(fresh_user.stats.pluck(:year, :month).to_set).to eq(expected_months)
    end

    it 'skips Stat rows that already exist for the user' do
      fresh_user.stats.create!(year: 2027, month: 1, distance: 999)
      described_class.new(fresh_user, shifted_anchor).call

      preserved = fresh_user.stats.find_by(year: 2027, month: 1)
      expect(preserved.distance).to eq(999)
    end
  end

  describe 'Place finder' do
    let(:fresh_user) { create(:user) }

    it 'does not overwrite a pre-existing non-demo place at the same coordinates' do
      home = fixture['places'].find { |p| p['key'] == 'home' }
      existing = Place.create!(
        user_id: fresh_user.id,
        name: 'My Real Home',
        latitude: home['lat'],
        longitude: home['lon'],
        demo: false
      )

      described_class.new(fresh_user, anchor).call

      expect(existing.reload.demo).to be(false)
      expect(existing.name).to eq('My Real Home')
      expect(Place.demo.where(user_id: fresh_user.id, latitude: home['lat'], longitude: home['lon']).count).to eq(1)
    end
  end

  describe 'Tag finder' do
    let(:fresh_user) { create(:user) }

    it 'reuses a pre-existing user tag with the same name and leaves it non-demo' do
      existing = fresh_user.tags.create!(name: 'home', color: '#abc123', demo: false)

      described_class.new(fresh_user, anchor).call

      expect(fresh_user.tags.where(name: 'home').count).to eq(1)
      expect(existing.reload.demo).to be(false)
    end

    it 'does not overwrite icon or color of a pre-existing user tag' do
      existing = fresh_user.tags.create!(
        name: 'home',
        icon: '🚀',
        color: '#abc123',
        demo: false
      )

      described_class.new(fresh_user, anchor).call

      expect(existing.reload.icon).to eq('🚀')
      expect(existing.color).to eq('#abc123')
    end
  end

  describe 'Trip seeding' do
    let(:fresh_user) { create(:user) }

    it 'does not enqueue Trips::CalculateAllJob for the demo trip' do
      expect { described_class.new(fresh_user, anchor).call }
        .not_to have_enqueued_job(Trips::CalculateAllJob)
    end
  end

  describe 'Tracks seeding' do
    let(:fresh_user) { create(:user) }
    let(:import) { create(:import, user: fresh_user, demo: true) }

    before do
      DemoData::PointsSeeder.new(fresh_user, import, anchor).call
      described_class.new(fresh_user, anchor).call
    end

    it 'creates one demo track per fixture track' do
      expect(fresh_user.tracks.demo.count).to eq(fixture['tracks'].length)
    end

    it 'creates a TrackSegment per track' do
      expect(TrackSegment.joins(:track).where(tracks: { user_id: fresh_user.id }).count)
        .to eq(fresh_user.tracks.demo.count)
    end

    it 'links points to tracks via track_id' do
      linked = fresh_user.points.where.not(track_id: nil).count
      expect(linked).to be > 0
    end
  end
end
