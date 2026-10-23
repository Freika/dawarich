# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Polish I18n pluralization' do
  def more_countries(count, locale)
    I18n.t('insights.country_ribbon.more_countries', count:, locale:)
  end

  it 'uses the Polish few and many forms' do
    expect(more_countries(1, :pl)).to eq('+1 kraj więcej')
    expect(more_countries(3, :pl)).to eq('+3 kraje więcej')
    expect(more_countries(22, :pl)).to eq('+22 kraje więcej')
    expect(more_countries(5, :pl)).to eq('+5 krajów więcej')
    expect(more_countries(12, :pl)).to eq('+12 krajów więcej')
    expect(more_countries(0, :pl)).to eq('+0 krajów więcej')
  end

  it 'uses the Polish few and many forms in Rails time distances' do
    I18n.with_locale(:pl) do
      expect(ActionController::Base.helpers.distance_of_time_in_words(0, 3.minutes)).to eq('3 minuty')
      expect(ActionController::Base.helpers.distance_of_time_in_words(0, 5.minutes)).to eq('5 minut')
    end
  end

  it 'maps counts to CLDR Polish plural categories' do
    rule = I18n.t('i18n.plural.rule', locale: :pl, resolve: false)

    expect([1].map(&rule)).to all(eq(:one))
    expect([2, 4, 22, 104, -3].map(&rule)).to all(eq(:few))
    expect([0, 5, 11, 12, 14, 21, 25, 112].map(&rule)).to all(eq(:many))
    expect([1.5, '5'].map(&rule)).to all(eq(:other))
  end

  it 'renders few and many forms for Polish count keys' do
    I18n.with_locale(:pl) do
      expect(I18n.t('trips.trip.country_count', count: 3)).to eq('3 kraje')
      expect(I18n.t('trips.trip.country_count', count: 5)).to eq('5 krajów')
      expect(I18n.t('places.drawer.visit_count', count: 3)).to eq('3 wizyty')
      expect(I18n.t('places.drawer.visit_count', count: 5)).to eq('5 wizyt')
      expect(I18n.t('javascript.selection.points', count: 24)).to eq('24 punkty')
    end
  end

  it 'falls back to other for Polish keys without few or many' do
    expect(I18n.t('trips.trip.day_count', count: 3, locale: :pl)).to eq('3 dni')
  end

  it 'keeps one/other pluralization for the other locales' do
    {
      en: ['+1 more country', '+5 more countries'],
      de: ['+1 weiteres Land', '+5 weitere Länder'],
      es: ['+1 país más', '+5 países más'],
      fr: ['+1 autre pays', '+5 autres pays'],
      ca: ['+1 país més', '+5 països més'],
      zh: ['还有 1 个国家', '还有 5 个国家']
    }.each do |locale, (one, other)|
      expect([more_countries(1, locale), more_countries(5, locale)]).to eq([one, other])
    end
  end
end
