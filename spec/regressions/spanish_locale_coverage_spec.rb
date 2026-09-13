# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Spanish locale coverage' do
  def deep_merge(target, additions)
    target.merge(additions) do |_key, old_value, new_value|
      old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
    end
  end

  def locale_tree(locale)
    Dir[Rails.root.join('config/locales/*.yml')].sort.each_with_object({}) do |path, translations|
      document = YAML.safe_load_file(path, aliases: true)
      next unless document.key?(locale)

      translations.replace(deep_merge(translations, document.fetch(locale)))
    end
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

  let(:english) { flatten(locale_tree('en')) }
  let(:spanish) { flatten(locale_tree('es')) }
  let(:fragile_token_pattern) do
    %r!
      %\{[^}]+\} |
      \#\{[^}]+\} |
      <[^>]+> |
      https?://[^\s"']+ |
      [\w.+-]+@[\w.-]+\.[A-Za-z]{2,} |
      &[A-Za-z]+; |
      \{[zxy]\}
    !x
  end

  it 'contains every English locale leaf with the same value type' do
    missing = english.keys - spanish.keys
    mismatched = english.filter_map do |path, value|
      next if missing.include?(path) || spanish.fetch(path).instance_of?(value.class)

      path.join('.')
    end

    expect(missing.map { |path| path.join('.') }).to be_empty
    expect(mismatched).to be_empty
  end

  it 'preserves interpolation, markup, URL, and template tokens' do
    mismatched = english.filter_map do |path, value|
      next unless value.is_a?(String)

      english_tokens = value.scan(fragile_token_pattern).sort
      spanish_tokens = spanish.fetch(path).scan(fragile_token_pattern).sort
      path.join('.') unless english_tokens == spanish_tokens
    end

    expect(mismatched).to be_empty
  end

  it 'provides Spanish Rails localization data' do
    I18n.with_locale(:es) do
      expect(I18n.l(Date.new(2026, 3, 4), format: :long)).to eq('4 de marzo de 2026')
      expect(I18n.l(Date.new(2026, 3, 4), format: :medium_padded)).to eq('04 mar 2026')
      expect(I18n.l(Date.new(2026, 3, 8), format: '%A')).to eq('domingo')
      expect(I18n.t('datetime.distance_in_words.x_minutes', count: 3)).to eq('3 minutos')
      expect(I18n.t('errors.messages.blank')).to eq('no puede estar en blanco')
    end
  end
end
