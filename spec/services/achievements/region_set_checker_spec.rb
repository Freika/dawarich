# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::RegionSetChecker do
  let(:user) { create(:user) }
  let(:base_ts) { DateTime.new(2026, 1, 1).to_i }
  let(:bavaria) { 'MULTIPOLYGON (((11.0 48.0, 11.0 49.0, 12.0 49.0, 12.0 48.0, 11.0 48.0)))' }

  def exploration
    Achievements::Progress.find_by(user: user, achievement_key: 'exploration')
  end

  def create_dwell_points(count: 8, lon: 11.5, lat: 48.5, step: 600, start_at: base_ts)
    count.times do |i|
      create(:point, user:, longitude: lon, latitude: lat, timestamp: start_at + (i * step))
    end
  end

  def seed_germany(with_country_id: true)
    create(:region, code: 'DE-BY', geom: bavaria)
    germany = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU', geom: bavaria)
    create_dwell_points
    user.points.update_all(country_id: germany.id) if with_country_id
  end

  describe 'the two mechanisms' do
    before { seed_germany }

    it 'credits the subdivision and the country from one pass' do
      described_class.new(user, notify: false).call

      expect(exploration.state['earned'].keys).to include('DE-BY', 'DE')
    end

    it 'keeps a single shared cursor' do
      described_class.new(user, notify: false).call

      expect(exploration.state['cursor']).to eq(base_ts + (7 * 600))
      expect(exploration.state['point_id_cursor']).to eq(user.points.maximum(:id))
      expect(exploration.state['calculation_version']).to eq(described_class::CALCULATION_VERSION)
      expect(exploration.state['threshold_seconds']).to eq(60.minutes.to_i)
    end

    it 'withholds the country award until every subdivision is earned' do
      described_class.new(user, notify: false).call

      expect(user.user_achievements.pluck(:achievement_key)).not_to include('country_de')
    end

    it 'never revokes an earned code' do
      described_class.new(user, notify: false).call
      user.points.delete_all
      create_dwell_points(count: 2, lon: 0.5, lat: 0.5)
      described_class.new(user, notify: false).call

      expect(exploration.state['earned']).to have_key('DE-BY')
    end

    it 'does not accumulate dwell twice when re-run against an unchanged cursor' do
      described_class.new(user, notify: false).call
      dwell = exploration.state['dwell'].dup

      described_class.new(user, notify: false).call

      expect(exploration.state['dwell']).to eq(dwell)
    end
  end

  describe 'flat countries' do
    let(:normandy) { 'MULTIPOLYGON (((2.0 48.0, 2.0 49.0, 3.0 49.0, 3.0 48.0, 2.0 48.0)))' }

    before do
      france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: normandy)
      create_dwell_points(lon: 2.5, lat: 48.5)
      user.points.update_all(country_id: france.id)
    end

    it 'awards a flat country as soon as it is visited' do
      described_class.new(user, notify: false).call

      expect(user.user_achievements.pluck(:achievement_key)).to include('country_fr')
    end

    it 'describes flat-country completion as a country, not a region' do
      described_class.new(user, notify: true).call

      expect(user.notifications.pluck(:content)).to include('You explored this country.')
    end
  end

  describe 'country_id fallback' do
    before { seed_germany(with_country_id: false) }

    it 'still earns the country through the spatial path' do
      described_class.new(user, notify: false).call

      expect(exploration.state['earned']).to have_key('DE')
    end
  end

  describe 'notifications' do
    before { seed_germany }

    it 'announces a subdivision through its country set' do
      described_class.new(user, notify: true).call

      expect(user.notifications.pluck(:title)).to include('Bavaria explored!')
    end

    it 'announces a country through its continent set' do
      described_class.new(user, notify: true).call

      expect(user.notifications.pluck(:title)).to include('Germany explored!')
      expect(user.notifications.pluck(:content)).to include('Europe Explorer: 1/50 countries visited.')
    end

    it 'collapses a bulk earn into one digest instead of a notification flood' do
      stub_const("#{described_class}::REGION_NOTIFY_CAP", 1)

      described_class.new(user, notify: true).call

      titles = user.notifications.pluck(:title)
      expect(titles).to include('2 new areas explored!')
      expect(titles).not_to include('Bavaria explored!')
    end

    it 'sends nothing when notifications are off' do
      described_class.new(user, notify: false).call

      expect(user.notifications).to be_empty
    end

    it 'is idempotent on re-run' do
      described_class.new(user, notify: true).call

      expect { described_class.new(user, notify: true).call }.not_to change(Notification, :count)
    end

    it 'writes notifications in the user locale' do
      user.persist_locale!(:de)

      described_class.new(user, notify: true).call

      expect(user.notifications.pluck(:title)).to include('Bavaria erkundet!')
    end
  end

  describe 'historical import recompute' do
    before { seed_germany }

    it 'replaces dwell rather than doubling it' do
      described_class.new(user, notify: false).call
      first = exploration.state['dwell']['DE-BY']

      described_class.new(user, notify: false, oldest_timestamp: base_ts - 1000).call

      expect(exploration.state['dwell']['DE-BY']).to eq(first)
    end

    it 'clears current dwell when every contributing point was deleted' do
      described_class.new(user, notify: false).call
      user.points.delete_all

      described_class.new(user, notify: false, oldest_timestamp: base_ts).call

      expect(exploration.reload.state['dwell']).to be_empty
      expect(exploration.state['earned']).to have_key('DE-BY')
    end

    it 'recomputes when the corrected point is exactly on the cursor boundary' do
      described_class.new(user, notify: false).call
      latest_point = user.points.order(:timestamp).last
      latest_point.destroy!

      described_class.new(user, notify: false, oldest_timestamp: latest_point.timestamp).call

      expect(exploration.reload.state['dwell']['DE-BY']).to eq(3_600)
    end
  end

  describe 'older rows becoming eligible' do
    it 'recaptures their global timestamp during a forced rebuild' do
      france_geom = 'MULTIPOLYGON (((2 48, 2 49, 3 49, 3 48, 2 48)))'
      france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: france_geom)
      future_points = 2.times.map do |index|
        create(:point, user: user, longitude: 2.5, latitude: 48.5, country_id: france.id,
                       timestamp: base_ts + 10_000 + (index * 600), anomaly: true)
      end
      seed_germany
      Point.where(id: future_points.map(&:id)).update_all(country_id: france.id)
      described_class.new(user, notify: false).call
      expect(exploration.state['cursor']).to eq(base_ts + 4_200)

      Point.where(id: future_points.map(&:id)).update_all(anomaly: false)
      described_class.new(user, notify: false, oldest_timestamp: base_ts).call

      expect(exploration.reload.state['cursor']).to eq(base_ts + 10_600)
      expect(exploration.state['dwell']['FR']).to eq(600)
    end
  end

  describe 'buffered device uploads' do
    before { seed_germany }

    it 'recomputes when newly inserted rows fall behind the timestamp cursor' do
      described_class.new(user, notify: false).call
      previous_point_id = exploration.state['point_id_cursor']
      france_geom = 'MULTIPOLYGON (((2.0 48.0, 2.0 49.0, 3.0 49.0, 3.0 48.0, 2.0 48.0)))'
      france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: france_geom)
      create_dwell_points(lon: 2.5, lat: 48.5, start_at: base_ts - 10_000)
      user.points.where('id > ?', previous_point_id).update_all(country_id: france.id)

      described_class.new(user, notify: false).call

      expect(exploration.reload.state['earned']).to have_key('FR')
      expect(exploration.state['point_id_cursor']).to eq(user.points.maximum(:id))
      expect(exploration.state['point_id_cursor']).to be > previous_point_id
    end

    it 'recaptures both bounds before retrying a stale full recomputation' do
      described_class.new(user, notify: false).call
      checker = described_class.new(user, notify: false, oldest_timestamp: base_ts - 1)
      original_commit = checker.method(:commit)
      attempts = 0

      allow(checker).to receive(:commit) do |deltas, **arguments|
        attempts += 1
        if attempts == 1
          france_geom = 'MULTIPOLYGON (((2.0 48.0, 2.0 49.0, 3.0 49.0, 3.0 48.0, 2.0 48.0)))'
          france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: france_geom)
          create_dwell_points(lon: 2.5, lat: 48.5, start_at: base_ts + 10_000)
          user.points.where(country_id: nil).update_all(country_id: france.id)
          described_class.new(user, notify: false).call
          false
        else
          original_commit.call(deltas, **arguments)
        end
      end

      checker.call

      expect(exploration.reload.state['dwell']['FR']).to eq(4_200)
      expect(exploration.state['cursor']).to eq(base_ts + 14_200)
      expect(attempts).to eq(2)
    end
  end

  describe 'when dwell stays below the threshold' do
    before do
      create(:region, code: 'DE-BY', geom: bavaria)
      create_dwell_points(count: 2)
    end

    it 'accumulates dwell without earning' do
      described_class.new(user, notify: false).call

      expect(exploration.state['dwell']['DE-BY']).to eq(600)
      expect(exploration.state['earned']).to be_empty
    end

    it 're-evaluates stored dwell when the threshold changes without new points' do
      described_class.new(user, notify: false).call
      user.update!(settings: user.settings.merge('min_minutes_spent_in_city' => 10))

      described_class.new(user, notify: false).call

      expect(exploration.reload.state['earned']).to have_key('DE-BY')
      expect(exploration.state['threshold_seconds']).to eq(10.minutes.to_i)
    end

    it 'does not rewind the cursor when points were deleted before a threshold-only pass' do
      described_class.new(user, notify: false).call
      original_cursor = exploration.state['cursor']
      user.points.order(timestamp: :desc).first.destroy!
      user.update!(settings: user.settings.merge('min_minutes_spent_in_city' => 10))

      described_class.new(user, notify: false).call

      expect(exploration.reload.state['cursor']).to eq(original_cursor)
      expect(exploration.state['earned']).to have_key('DE-BY')
    end
  end

  describe 'when the user has no usable points' do
    it 'creates no progress row at all' do
      described_class.new(user, notify: false).call

      expect(exploration).to be_nil
    end

    it 'ignores points that carry no coordinates' do
      create(:point, user:, timestamp: base_ts).update_column(:lonlat, nil)

      described_class.new(user, notify: false).call

      expect(exploration).to be_nil
    end
  end
end
