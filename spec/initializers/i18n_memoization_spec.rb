# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe 'I18n lookup memoization' do
  around do |example|
    backend = I18n.backend
    load_path = I18n.load_path
    fallbacks = I18n.fallbacks
    I18n.backend = Class.new(I18n::Backend::Simple) { include I18n::Backend::Fallbacks }.new
    I18n.load_path = []
    I18n.fallbacks = I18n::Locale::Fallbacks.new(de: :en)
    example.run
  ensure
    I18n.backend = backend
    I18n.load_path = load_path
    I18n.fallbacks = fallbacks
  end

  def backend_lookups(&block)
    calls = 0
    trace = TracePoint.new(:call) do |event|
      calls += 1 if event.defined_class == I18n::Backend::Simple::Implementation && event.method_id == :lookup
    end
    trace.enable(&block)
    calls
  end

  def warm_translation(key = 'greeting', **options)
    I18n.backend.store_translations(:en, greeting: 'Hello %<name>s')
    I18n.backend.store_translations(:de, greeting: 'Hallo %<name>s')
    I18n.backend.eager_load!
    I18n.t(key, locale: :de, name: 'Ada', **options)
  end

  it 'reuses lookups with identical fallback, interpolation, plural and missing-key behavior' do
    warm_translation
    I18n.backend.store_translations(:en, only_english: 'Hello %<name>s',
                                       items: { one: 'One', other: '%<count>d items' })
    outputs = lambda do |name, count|
      [I18n.t('greeting', locale: :de, name: name),
       I18n.t('only_english', locale: :de, name: name),
       I18n.t('items', locale: :de, count: count),
       I18n.t('missing', locale: :de, default: name),
       I18n.t('only_english', locale: :de, fallback: false, default: 'Absent')]
    end
    expect(outputs.call('Ada', 1)).to eq(['Hallo Ada', 'Hello Ada', 'One', 'Ada', 'Absent'])
    expect(backend_lookups do
      expect(outputs.call('Grace', 3)).to eq(['Hallo Grace', 'Hello Grace', '3 items', 'Grace', 'Absent'])
    end).to eq(0)
  end

  it 'invalidates cached lookups and missing translations when translations are stored' do
    warm_translation
    expect(I18n.t('new_key', locale: :de, default: 'Absent')).to eq('Absent')
    expect(backend_lookups { I18n.t('greeting', locale: :de, name: 'Ada') }).to eq(0)
    I18n.backend.store_translations(:de, greeting: 'Guten Tag %<name>s', new_key: 'Present')
    expect(I18n.t('greeting', locale: :de, name: 'Grace')).to eq('Guten Tag Grace')
    expect(I18n.t('new_key', locale: :de)).to eq('Present')
  end

  it 'reads changed locale files after reload instead of reusing stale lookups' do
    Dir.mktmpdir('locale-reload') do |directory|
      path = File.join(directory, 'en.yml')
      File.write(path, { en: { greeting: 'Hello %<name>s' } }.to_yaml)
      I18n.load_path = [path]
      expect(I18n.t('greeting', locale: :de, name: 'Ada')).to eq('Hello Ada')
      expect(backend_lookups { I18n.t('greeting', locale: :de, name: 'Grace') }).to eq(0)
      File.write(path, { en: { greeting: 'Welcome %<name>s' } }.to_yaml)
      I18n.reload!
      expect(I18n.t('greeting', locale: :de, name: 'Grace')).to eq('Welcome Grace')
    end
  end
end
