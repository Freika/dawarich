# frozen_string_literal: true

module PhoenixBuildInputs
  LOCALES = 'config/locales/0_vendor'
  ASSETS = 'vendor/assets'
  INTER = %w[italic roman].product(%w[alternates cyrillic extra greek latin-ext latin symbols vietnamese])
                          .map { |style, subset| "Inter-#{style}.#{subset}.var.woff2" }

  def self.javascripts(gem, names, from: 'app/assets/javascripts')
    names.map { |name| [gem, "#{from}/#{name}", "#{ASSETS}/javascripts/#{name}"] }
  end

  VENDORED = [
    ['activesupport', 'lib/active_support/locale/en.yml', "#{LOCALES}/01_active_support.en.yml"],
    ['activemodel', 'lib/active_model/locale/en.yml', "#{LOCALES}/02_active_model.en.yml"],
    ['activerecord', 'lib/active_record/locale/en.yml', "#{LOCALES}/03_active_record.en.yml"],
    ['actionview', 'lib/action_view/locale/en.yml', "#{LOCALES}/04_action_view.en.yml"],
    *%w[de en es fr pl].map { |l| ['validate_url', "lib/locale/#{l}.yml", "#{LOCALES}/05_validate_url.#{l}.yml"] },
    ['responders', 'lib/responders/locales/en.yml', "#{LOCALES}/06_responders.en.yml"],
    ['devise', 'config/locales/en.yml', "#{LOCALES}/07_devise.en.yml"],
    ['kaminari-core', 'config/locales/kaminari.yml', "#{LOCALES}/08_kaminari.en.yml"],
    *javascripts('actionview', %w[rails-ujs.js]),
    *javascripts('actioncable', %w[actioncable.js actioncable.esm.js]),
    *javascripts('activestorage', %w[activestorage.js activestorage.esm.js]),
    *javascripts('actiontext', %w[actiontext.js actiontext.esm.js]),
    *javascripts('action_text-trix', %w[trix.js]),
    ['action_text-trix', 'app/assets/stylesheets/trix.css', "#{ASSETS}/stylesheets/trix.css"],
    *javascripts('turbo-rails', %w[turbo.js turbo.min.js turbo.min.js.map]),
    *javascripts('stimulus-rails', %w[stimulus.js stimulus.min.js stimulus.min.js.map stimulus-loading.js
                                      stimulus-autoloader.js stimulus-importmap-autoloader.js]),
    *javascripts('chartkick', %w[chartkick.js Chart.bundle.js], from: 'vendor/assets/javascripts'),
    ['tailwindcss-rails', 'app/assets/stylesheets/inter-font.css', "#{ASSETS}/stylesheets/inter-font.css"],
    *INTER.map { |name| ['tailwindcss-rails', "app/assets/fonts/#{name}", "#{ASSETS}/fonts/#{name}"] }
  ].freeze

  ManifestResolver = Struct.new(:manifest) do
    def path_to_asset(path)
      return path if path.start_with?('/') || path.match?(%r{\A(?:[-a-z]+://|cid:|data:|//)}i)

      "/assets/#{assets.fetch(path)}"
    end

    def assets
      @assets ||= JSON.parse(File.read(manifest)).fetch('assets')
    end
  end

  module_function

  def gem_file(gem, path)
    File.join(Gem.loaded_specs.fetch(gem).full_gem_path, path)
  end

  def vendor!
    VENDORED.each do |gem, source, target|
      FileUtils.mkdir_p(Rails.root.join(File.dirname(target)))
      FileUtils.cp(gem_file(gem, source), Rails.root.join(target))
    end
  end

  def i18n_json
    JSON.generate(I18n.backend.translations(do_init: true).slice(*I18n.available_locales))
  end

  def achievements_json
    definitions = Achievements::Registry.all.map do |definition|
      {
        'key' => definition.key, 'kind' => definition.kind, 'level' => definition.level.to_s,
        'flat' => definition.flat?, 'threshold' => definition.threshold, 'total' => definition.total,
        'target' => definition.target, 'regions' => definition.regions, 'region_codes' => definition.region_codes,
        'names' => I18n.available_locales.to_h do |locale|
          [locale.to_s, I18n.with_locale(locale) { Achievements::SetPresenter.new(definition:).name }]
        end
      }
    end
    JSON.generate('definitions' => definitions)
  end

  def time_zones_json
    JSON.generate('options' => Object.new.extend(UserHelper).settings_time_zone_options)
  end

  def importmap_json(manifest = nil)
    return Rails.application.importmap.to_json(resolver: ActionController::Base.helpers) unless manifest

    Rails.application.importmap.to_json(resolver: ManifestResolver.new(manifest), cache_key: "phoenix:#{manifest}")
  end

  def compile_assets(dir, manifest)
    FileUtils.mkdir_p(File.dirname(manifest))
    Sprockets::Manifest.new(Rails.application.assets, dir, manifest).compile(Rails.application.config.assets.precompile)
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
