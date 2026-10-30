# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CollectiblePresenter do
  let(:data) do
    { 'name' => 'Demo', 'latitude' => 0.5, 'longitude' => 21, 'timezone' => 'UTC',
      'progress' => 4, 'target' => 4, 'season_mask' => 15,
      'evidence' => 4.times.map { |i| { 'season' => i, 'at' => "2020-0#{i + 1}-01T12:00:00Z" } } }
  end
  let(:card) { Achievements::Collectible.new(series: 'seasons', subject_key: 'place:1', level: 1, earned_at: Time.utc(2020, 4, 1), data: data) }

  it 'renders tropical periods, translated rules and all card labels in every achievement locale' do
    %i[en ca de es fr pl zh].each do |locale|
      I18n.with_locale(locale) do
        presenter = described_class.new(card)
        expect(presenter.name).not_to include('Translation missing')
        expect(presenter.evidence_rows.pluck(:label)).to eq(4.times.map { |i|
          I18n.t("achievements.collections.periods.#{i}", raise: true)
        })
        Achievements::Collectible::SERIES.each do |series|
          expect(I18n.t("achievements.collections.rules.#{series}", raise: true)).to be_present
          expect(I18n.t("achievements.collections.series.#{series}", raise: true)).to be_present
        end
        [1, 3, 5].each do |years|
          expect(I18n.t('achievements.collections.return_years', count: years, raise: true)).to be_present
        end
      end
    end
  end

  it 'reverses season labels in the southern hemisphere independently of profile timezone' do
    card.data = data.merge('latitude' => -33)
    expect(described_class.new(card).evidence_rows.pluck(:label)).to eq(%w[Summer Autumn Winter Spring])
  end
end

RSpec.describe Achievements::CollectiblePresenter, 'public stage' do
  let(:city) do
    Achievements::Collectible.new(series: 'city', subject_key: 'city:1', level: 3, earned_at: Time.utc(2022, 12, 8),
                                  data: { 'name' => 'Berlin', 'progress' => 12.4, 'levels' => { '3' => '2022-12-08' } })
  end

  it 'climbs the city level ladder up to the current level' do
    ladder = described_class.new(city).ladder

    expect(ladder.pluck(:percent)).to eq([1, 5, 10, 25])
    expect(ladder.pluck(:state)).to eq(%i[done done current next])
  end

  it 'names the reached city level in the headline and the next level after it' do
    presenter = described_class.new(city)

    expect(presenter.headline).to eq('10% of Berlin explored')
    expect(presenter.next_level_percent).to eq(25)
  end

  it 'has no ladder or next level once the top city level is reached' do
    city.level = 4

    expect(described_class.new(city).next_level_percent).to be_nil
  end

  it 'keeps the card name as headline and no ladder for cards without levels' do
    seasons = Achievements::Collectible.new(series: 'seasons', subject_key: 'place:1', level: 1,
                                            data: { 'name' => 'Schlachtensee', 'progress' => 4, 'target' => 4 })
    presenter = described_class.new(seasons)

    expect(presenter.ladder).to be_nil
    expect(presenter.headline).to eq(presenter.name)
  end
end
