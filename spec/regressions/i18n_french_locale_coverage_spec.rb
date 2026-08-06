# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'French I18n locale coverage' do
  def placeholder_pattern
    /%\{[^}]+\}|%<[^>]+>[#0\- +]*\d*(?:\.\d+)?[a-zA-Z]|%%/
  end

  def flatten(value, path = [], result = {})
    case value
    when Hash
      value.each { |key, child| flatten(child, path + [key], result) }
    when Array
      value.each_with_index { |child, index| flatten(child, path + [index], result) }
    else
      result[path] = value
    end

    result
  end

  {
    'config/locales/en.yml' => 'config/locales/fr.yml',
    'config/locales/devise.en.yml' => 'config/locales/devise.fr.yml'
  }.each do |english_path, french_path|
    it "covers every key and interpolation in #{english_path}" do
      english = flatten(YAML.safe_load_file(Rails.root.join(english_path), aliases: true).fetch('en'))
      french = flatten(YAML.safe_load_file(Rails.root.join(french_path), aliases: true).fetch('fr'))
      missing = english.keys - french.keys
      type_mismatches = english.keys.filter_map do |path|
        next unless french.key?(path)
        next if english.fetch(path).instance_of?(french.fetch(path).class)

        path.join('.')
      end
      placeholder_mismatches = english.keys.filter_map do |path|
        next unless english.fetch(path).is_a?(String) && french[path].is_a?(String)
        next if english.fetch(path).scan(placeholder_pattern).sort == french.fetch(path).scan(placeholder_pattern).sort

        path.join('.')
      end

      expect(missing.map { |path| path.join('.') }).to be_empty
      expect(type_mismatches).to be_empty
      expect(placeholder_mismatches).to be_empty
    end
  end

  it 'loads French translations and localized date names through Rails' do
    expect(I18n.available_locales).to include(:fr)

    I18n.with_locale(:fr) do
      expect(I18n.t('javascript.map_controls.add_visit')).to eq('Ajouter une visite')
      expect(I18n.l(Date.new(2026, 8, 5), format: :long)).to eq('5 août 2026')
    end
  end
end
