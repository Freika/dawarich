# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'phoenix:achievements' do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:achievements') }

  def export
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'achievements.json')
      Rake::Task['phoenix:achievements'].reenable
      Rake::Task['phoenix:achievements'].invoke(path)
      JSON.parse(File.read(path))
    ensure
      Rake::Task['phoenix:achievements'].reenable
    end
  end

  it 'exports every definition with its regions and per-locale names' do
    data = export
    country_de = data['definitions'].find { |definition| definition['key'] == 'country_de' }
    presenter = Achievements::SetPresenter.new(definition: Achievements::Registry.find('country_de'))

    expect(data['definitions'].size).to eq(Achievements::Registry.all.size)
    expect(country_de['level']).to eq('subdivision')
    expect(country_de['region_codes']).to include('DE-SN')
    expect(country_de['names']['de']).to eq(I18n.with_locale(:de) { presenter.name })
  end

  it 'exports the card, geography and name of every definition as the registry holds them' do
    fields = %w[key name country continent parent_key card]
    expected = Achievements::Registry.all.map do |definition|
      fields.index_with { |field| definition.public_send(field) }
    end

    expect(export['definitions'].map { |definition| definition.slice(*fields) })
      .to eq(JSON.parse(JSON.generate(expected)))
  end

  it 'exports the transliteration table I18n.transliterate uses in every available locale' do
    table = export.fetch('transliteration')
    defaults = I18n::Backend::Transliterator::HashTransliterator::DEFAULT_APPROXIMATIONS

    I18n.available_locales.each do |locale|
      approximations = table.fetch('default').merge(table.fetch('rules').fetch(locale.to_s, {}))

      (defaults.keys | approximations.keys | ['中']).each do |char|
        expect(approximations.fetch(char, '?')).to eq(I18n.with_locale(locale) { I18n.transliterate(char) })
      end
    end
  end
end
