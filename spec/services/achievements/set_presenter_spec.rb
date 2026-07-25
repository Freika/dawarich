# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::SetPresenter do
  def presenter(key, earned: {}, celebrated: {})
    described_class.new(
      definition: Achievements::Registry.find(key),
      state: { 'earned' => earned, 'celebrated' => celebrated }
    )
  end

  describe 'scoping the global state to one set' do
    it 'ignores earned codes belonging to other sets' do
      set = presenter('country_de', earned: { 'DE-BY' => '2026-05-01', 'FR' => '2026-06-01',
                                              'US-CA' => '2026-06-02' })

      expect(set.earned.keys).to eq(['DE-BY'])
      expect(set.earned_count).to eq(1)
    end
  end

  describe 'a gridded country' do
    it 'reports partial progress' do
      set = presenter('country_de', earned: { 'DE-BY' => '2026-05-01', 'DE-SN' => '2026-05-02' })

      expect(set.percent).to eq(13)
      expect(set).not_to be_locked
      expect(set).not_to be_completed
      expect(set.earned_label).to eq('2/16 regions')
    end

    it 'reports completion dated at the last region' do
      earned = Achievements::Registry.find('country_de').region_codes.index_with { '2026-05-01' }
      set = presenter('country_de', earned: earned.merge('DE-BY' => '2026-07-20'))

      expect(set).to be_completed
      expect(set.completed_on).to eq(Date.new(2026, 7, 20))
      expect(set.earned_label).to eq('Unlocked · 20 Jul 2026')
    end

    it 'is locked with nothing earned' do
      expect(presenter('country_de')).to be_locked
      expect(presenter('country_de').earned_label).to eq('Locked')
    end
  end

  describe 'a flat country' do
    it 'completes on a single country code' do
      set = presenter('country_fr', earned: { 'FR' => '2026-05-01' })

      expect(set).to be_flat
      expect(set.target).to eq(1)
      expect(set).to be_completed
      expect(set.percent).to eq(100)
    end
  end

  describe 'a continent' do
    it 'counts its member countries' do
      set = presenter('continent_europe', earned: { 'DE' => '2026-05-01', 'FR' => '2026-05-02',
                                                    'DE-BY' => '2026-05-01' })

      expect(set.level).to eq(:country)
      expect(set.earned_count).to eq(2)
      expect(set.total).to eq(50)
    end

    it 'builds country child cards from the country definitions' do
      set = presenter('continent_europe', earned: { 'DE' => '2026-05-01' })
      germany = set.region_cards.find { |card| card[:name] == 'Germany' }

      expect(germany[:key]).to eq('country_de')
      expect(germany[:map_lat]).to be_within(0.5).of(51.087)
    end

    it 'shows a gridded country at its own subdivision progress, not merely visited' do
      set = presenter('continent_europe', earned: { 'DE' => '2026-05-01', 'DE-BY' => '2026-05-02',
                                                    'DE-SN' => '2026-05-03', 'DE-BE' => '2026-05-04' })
      germany = set.region_cards.find { |card| card[:name] == 'Germany' }

      expect(germany[:percent]).to eq(19)
      expect(germany[:completed]).to be(false)
      expect(germany[:locked]).to be(false)
      expect(germany[:earned_label]).to eq('3/16 regions')
    end

    it 'marks a visited country with no earned subdivisions as visited, not locked' do
      set = presenter('continent_europe', earned: { 'DE' => '2026-05-01' })
      germany = set.region_cards.find { |card| card[:name] == 'Germany' }

      expect(germany[:locked]).to be(false)
      expect(germany[:completed]).to be(false)
      expect(germany[:earned_label]).to eq('Visited')
    end

    it 'completes a gridded country only when every subdivision is earned' do
      all = Achievements::Registry.find('country_de').region_codes.index_with { '2026-05-01' }
      set = presenter('continent_europe', earned: all.merge('DE' => '2026-05-01'))
      germany = set.region_cards.find { |card| card[:name] == 'Germany' }

      expect(germany[:completed]).to be(true)
      expect(germany[:percent]).to eq(100)
    end

    it 'still completes a flat country on its own code' do
      set = presenter('continent_europe', earned: { 'FR' => '2026-05-01' })
      france = set.region_cards.find { |card| card[:name] == 'France' }

      expect(france[:completed]).to be(true)
      expect(france[:percent]).to eq(100)
    end

    it 'leaves flat countries unlinked' do
      set = presenter('continent_europe')
      france = set.region_cards.find { |card| card[:name] == 'France' }

      expect(france[:key]).to be_nil
    end

    it 'exposes the achievement key of a flat (leaf) country for sharing' do
      set = presenter('continent_europe')
      france = set.region_cards.find { |card| card[:name] == 'France' }
      germany = set.region_cards.find { |card| card[:name] == 'Germany' }

      expect(france[:share_key]).to eq('country_fr')
      expect(germany[:share_key]).to be_nil
    end
  end

  describe 'a world tier' do
    it 'measures against the threshold, not the universe' do
      earned = { 'DE' => '2026-01-01', 'FR' => '2026-02-01', 'IT' => '2026-03-01',
                 'ES' => '2026-04-01', 'PT' => '2026-05-01', 'NL' => '2026-06-01' }
      set = presenter('border_hopper', earned: earned)

      expect(set.target).to eq(5)
      expect(set).to be_completed
      expect(set.display_count).to eq(5)
      expect(set.completed_on).to eq(Date.new(2026, 5, 1))
    end
  end

  describe 'subdivision child cards' do
    before do
      create(:region, code: 'DE-BY', geom: 'MULTIPOLYGON (((11 48, 11 49, 12 49, 12 48, 11 48)))')
    end

    it 'centres a child on its own geometry' do
      set = presenter('country_de', earned: { 'DE-BY' => '2026-05-01' })
      bavaria = set.region_cards.find { |card| card[:name] == 'Bavaria' }

      expect(bavaria[:map_lat]).to be_within(0.01).of(48.5)
      expect(bavaria[:map_lon]).to be_within(0.01).of(11.5)
      expect(bavaria[:earned_label]).to eq('Unlocked · 1 May 2026')
    end
  end

  describe '#celebrate?' do
    let(:all_earned) { Achievements::Registry.find('country_de').region_codes.index_with { '2026-07-19' } }

    it 'is true when completed and not yet celebrated' do
      expect(presenter('country_de', earned: all_earned)).to be_celebrate
    end

    it 'is false once the key is recorded as celebrated' do
      set = presenter('country_de', earned: all_earned, celebrated: { 'country_de' => '2026-07-20T10:00:00Z' })

      expect(set).not_to be_celebrate
    end

    it 'is false while in progress' do
      expect(presenter('country_de', earned: { 'DE-BY' => '2026-05-01' })).not_to be_celebrate
    end
  end

  describe '#card_attributes' do
    it 'returns plain locals for the card partial' do
      set = presenter('country_de', earned: { 'DE-BY' => '2026-05-01', 'DE-SN' => '2026-05-02' })

      expect(set.card_attributes).to include(
        name: 'Germany Explorer',
        description: 'Spend time in all 16 regions of Germany.',
        rarity: 'Rare',
        place: 'Germany',
        percent: 13,
        completed: false,
        locked: false,
        earned_label: '2/16 regions'
      )
      expect(set.card_attributes[:map_zoom]).to be_positive
    end
  end
end
