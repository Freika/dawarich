# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'open3'

RSpec.describe PhoenixBuildInputs do
  it 'exports byte-identical translations in separate processes without callable ordinals' do
    exports = Array.new(2) do
      output, error, status = Open3.capture3(
        RbConfig.ruby, '-r', Rails.root.join('config/environment').to_s,
        '-r', Rails.root.join('lib/phoenix_build_inputs').to_s,
        '-e', 'STDOUT.write(PhoenixBuildInputs.i18n_json)'
      )
      expect(status.success?).to be(true), error
      output
    end

    expect(exports.first == exports.last).to be(true), 'fresh-process translation exports differ'
    translations = JSON.parse(exports.first)
    expect(translations.dig('en', 'number', 'nth')).not_to have_key('ordinals')
    expect(translations.dig('en', 'number', 'nth')).not_to have_key('ordinalized')
    expect(translations.dig('en', 'date', 'month_names')).to eq(I18n.t('date.month_names', locale: :en))
    expect(translations.dig('en', 'number', 'format')).to eq(I18n.t('number.format', locale: :en).stringify_keys)
  end

  describe PhoenixBuildInputs::ManifestResolver do
    it 'maps a logical path through the manifest and leaves absolute paths and URLs alone' do
      Dir.mktmpdir do |dir|
        manifest = File.join(dir, 'manifest.json')
        File.write(manifest, JSON.generate('assets' => { 'application.js' => 'application-abc.js' }))
        resolver = described_class.new(manifest)

        expect(resolver.path_to_asset('application.js')).to eq('/assets/application-abc.js')
        expect(resolver.path_to_asset('/maplibre/6.4.1/maplibre-gl.mjs')).to eq('/maplibre/6.4.1/maplibre-gl.mjs')
        expect(resolver.path_to_asset('https://cdn.example/x.js')).to eq('https://cdn.example/x.js')
        expect { resolver.path_to_asset('missing.js') }.to raise_error(KeyError)
      end
    end
  end

  def foreign?(file)
    ancestors = Pathname(file).descend.to_a
    gems = Gem.loaded_specs.values.map { |spec| Pathname(spec.full_gem_path) }
    ancestors.intersect?(gems) || ancestors.exclude?(Rails.root)
  end

  it 'compiles the precompile list into a directory, leaving public/ and config/ alone' do
    watched = [Rails.root.join('config/sprockets-manifest.json'), Rails.root.join('public/assets')]
    before = watched.map { |path| path.exist? && path.mtime }

    Dir.mktmpdir do |dir|
      manifest = File.join(dir, 'config/sprockets-manifest.json')
      described_class.compile_assets(File.join(dir, 'public/assets'), manifest)
      assets = JSON.parse(File.read(manifest)).fetch('assets')

      expect(assets.fetch('manifest.js'))
        .to eq('manifest-597b5199768f5efff6ec880a4180aec95099b04608cc46e56dfe4e0940ee4665.js')
      expect(File).to exist(File.join(dir, 'public/assets', "#{assets.fetch('application.css')}.gz"))
      expect(watched.map { |path| path.exist? && path.mtime }).to eq(before)
    end
  end

  describe 'vendored gem files' do
    it 'are byte copies of the installed gems' do
      stale = described_class::VENDORED.reject do |gem, source, target|
        Rails.root.join(target).exist? &&
          File.binread(described_class.gem_file(gem, source)) == File.binread(Rails.root.join(target))
      end

      expect(stale).to eq([])
    end

    it 'cover every gem locale file Rails loads for an available locale' do
      locales = I18n.available_locales.map(&:to_s)
      outside = I18n.load_path.map(&:to_s).select { |file| foreign?(file) }
      ymls = outside.select do |file|
        file.end_with?('.yml') && YAML.unsafe_load_file(file).keys.map(&:to_s).intersect?(locales)
      end
      vendored = described_class::VENDORED.select { |_, _, target| target.end_with?('.yml') }
                                          .map { |gem, source, _| described_class.gem_file(gem, source) }

      expect(ymls.sort).to eq(vendored.sort)
      expect(outside.reject { |file| file.end_with?('.yml') })
        .to eq([described_class.gem_file('activesupport', 'lib/active_support/locale/en.rb')])
    end

    it 'load right after the gems, before every application locale file' do
      app = I18n.load_path.map(&:to_s).select { |file| file.start_with?(Rails.root.join('config/locales').to_s) }
      vendored = described_class::VENDORED.filter_map do |_, _, target|
        Rails.root.join(target).to_s if target.end_with?('.yml')
      end

      expect(app.first(vendored.size)).to eq(vendored.sort)
    end

    it 'leave no precompiled asset resolving to a gem or a file outside the repository' do
      files = Rails.application.assets_manifest.find(Rails.application.config.assets.precompile).map(&:filename).uniq

      expect(files.select { |file| foreign?(file) }).to eq([])
    end
  end

  describe 'Rails behaviour the Elixir build mirrors' do
    let(:mirrored) do
      { 'sprockets' => '4.2.1', 'sprockets-rails' => '3.5.2', 'importmap-rails' => '2.2.3', 'i18n' => '1.15.2' }
    end

    it 'precompiles the assets Rails is configured to precompile' do
      compiler = Rails.root.join('app-phoenix/lib/dawarich/build/sprockets/compiler.ex').read

      expect(compiler[/@precompile ~w\(([^)]*)\)/, 1].split).to match_array(Rails.application.config.assets.precompile)
    end

    it 'runs the gem versions the Elixir build reproduces byte for byte' do
      versions = Gem.loaded_specs.slice(*mirrored.keys).transform_values { |spec| spec.version.to_s }

      expect(versions).to eq(mirrored), 'a gem the Elixir build mirrors changed version: run ' \
                                        '`mix test --only rails_parity` in app-phoenix, refresh the vectors in ' \
                                        'compiler_test.exs if it fails, then update this list'
    end

    it 'builds Tailwind in the image with the version tailwindcss-ruby gives Rails' do
      pinned = JSON.parse(Rails.root.join('package.json').read).dig('devDependencies', 'tailwindcss')

      expect(Gem.loaded_specs.fetch('tailwindcss-ruby').version.to_s).to eq(pinned)
    end
  end

  it 'writes the time-zone list through phoenix:time_zones' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:time_zones')

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'time_zones.json')
      Rake::Task['phoenix:time_zones'].reenable
      Rake::Task['phoenix:time_zones'].invoke(path)

      expect(File.read(path)).to eq(described_class.time_zones_json)
    ensure
      Rake::Task['phoenix:time_zones'].reenable
    end
  end

  it 'commits the time-zone list the helper builds from ActiveSupport zones at the committed offsets' do
    committed = Rails.root.join('app-phoenix/priv/time_zones.json').read
    offsets = JSON.parse(committed).fetch('options').to_h do |label, iana|
      [iana, Time.zone_offset(label[/\A\(GMT([+-]\d\d:\d\d)\) /, 1])]
    end
    zones = ActiveSupport::TimeZone::MAPPING.filter_map do |name, iana|
      ActiveSupport::TimeZone.create(name, offsets[iana], Struct.new(:name).new(iana)) if offsets.key?(iana)
    end
    allow(ActiveSupport::TimeZone).to receive(:all).and_return(zones.sort)

    expect(described_class.time_zones_json).to eq(committed)
  end

  it 'feeds Phoenix only YAML whose plain scalars mean the same under YAML 1.2' do
    files = Dir[Rails.root.join('config/locales/**/*.yml')] + Dir[Rails.root.join('config/achievements{.yml,/*.yml}')]

    expect(files.flat_map { |file| described_class.yaml_problems(file) }).to eq([])
  end

  it 'flags plain scalars YAML 1.2 reads differently, anchors, aliases, duplicate keys and version directives' do
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'x.yml')
      File.write(file, "a: yes\nb: 1_000\nc: &x 1\nd: *x\ne: 1\ne: 2\nf: plain\ng: 2\nh: ~\ni: 3.0\n" \
                       "j: 08\nk: 1e3\nl: 0o17\nm: +\n")
      versioned = File.join(dir, 'v.yml')
      File.write(versioned, "%YAML 1.1\n---\na: b\n")

      expect(described_class.yaml_problems(file)).to eq(
        ["#{file}:1 duplicate or merge key", "#{file}:1 \"yes\"", "#{file}:2 \"1_000\"",
         "#{file}:3 anchor, alias or tag", "#{file}:4 anchor, alias or tag",
         "#{file}:11 \"08\"", "#{file}:12 \"1e3\"", "#{file}:13 \"0o17\"", "#{file}:14 \"+\""]
      )
      expect(described_class.yaml_problems(versioned)).to eq(["#{versioned}:1 %YAML directive"])
    end
  end
end
