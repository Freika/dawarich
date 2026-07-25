# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::MigrateExplorationState do
  let(:user) { create(:user) }

  def exploration
    Achievements::Progress.find_by(user: user, achievement_key: 'exploration')
  end

  describe 'merging per-set rows' do
    before do
      create(:achievement_progress, user: user, achievement_key: 'explorer_germany',
                                    state: { 'earned' => { 'DE-BY' => '2026-05-01' },
                                             'dwell' => { 'DE-BY' => 9000 }, 'cursor' => 100 })
      create(:achievement_progress, user: user, achievement_key: 'border_hopper',
                                    state: { 'earned' => { 'DE' => '2026-03-02', 'FR' => '2026-04-01' },
                                             'dwell' => { 'DE' => 5000 }, 'cursor' => 400 })
    end

    it 'collapses every set into one exploration row' do
      described_class.new.call

      expect(exploration.state['earned']).to eq(
        'DE-BY' => '2026-05-01', 'DE' => '2026-03-02', 'FR' => '2026-04-01'
      )
    end

    it 'keeps the earliest date when a code is earned in several sets' do
      create(:achievement_progress, user: user, achievement_key: 'explorer_europe',
                                    state: { 'earned' => { 'DE' => '2026-01-15' } })

      described_class.new.call

      expect(exploration.state['earned']['DE']).to eq('2026-01-15')
    end

    it 'resets dwell and cursor so the backfill recomputes them exactly' do
      described_class.new.call

      expect(exploration.state['dwell']).to eq({})
      expect(exploration.state['cursor']).to eq(0)
    end

    it 'deletes the superseded per-set rows' do
      described_class.new.call

      expect(user.achievement_progresses.pluck(:achievement_key)).to contain_exactly('exploration')
    end
  end

  describe 'sharing carriers' do
    it 'keeps a shared row under its renamed key with empty state' do
      create(:achievement_progress, user: user, achievement_key: 'explorer_germany',
                                    sharing_enabled: true, sharing_uuid: 'abc-123',
                                    state: { 'earned' => { 'DE-BY' => '2026-05-01' } })

      described_class.new.call

      carrier = user.achievement_progresses.find_by(achievement_key: 'country_de')
      expect(carrier.sharing_uuid).to eq('abc-123')
      expect(carrier.sharing_enabled).to be(true)
      expect(carrier.state).to eq({})
      expect(exploration.state['earned']).to eq('DE-BY' => '2026-05-01')
    end
  end

  describe 'renaming awards' do
    it 'moves awards onto the new keys and leaves tiers alone' do
      create(:user_achievement, user: user, achievement_key: 'explorer_germany')
      create(:user_achievement, user: user, achievement_key: 'explorer_europe')
      create(:user_achievement, user: user, achievement_key: 'border_hopper')

      described_class.new.call

      expect(user.user_achievements.pluck(:achievement_key))
        .to contain_exactly('country_de', 'continent_europe', 'border_hopper')
    end

    it 'drops a duplicate award rather than violating the unique index' do
      create(:user_achievement, user: user, achievement_key: 'explorer_germany')
      create(:user_achievement, user: user, achievement_key: 'country_de')

      expect { described_class.new.call }.not_to raise_error
      expect(user.user_achievements.pluck(:achievement_key)).to contain_exactly('country_de')
    end
  end

  it 'is idempotent' do
    create(:achievement_progress, user: user, achievement_key: 'explorer_germany',
                                  state: { 'earned' => { 'DE-BY' => '2026-05-01' } })

    described_class.new.call
    expect { described_class.new.call }.not_to(change { exploration.reload.state })
  end
end
