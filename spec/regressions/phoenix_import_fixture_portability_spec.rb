# frozen_string_literal: true

require 'rails_helper'
require_relative '../../app-phoenix/scripts/parity/normal_import_formats_support'
require_relative '../../app-phoenix/scripts/parity/normal_import_create_support'

RSpec.describe NormalImportFormatsSupport do
  it 'verifies import fixture bytes without rewriting them' do
    Dir.mktmpdir do |dir|
      stub_const('NormalImportFormatsSupport::DIR', Pathname.new(dir))
      path = File.join(dir, 'result.json')
      File.binwrite(path, "{\n  \"error\": null\n}\n")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return(nil)
      expect(File).not_to receive(:write)
      expect(File).not_to receive(:binwrite)

      described_class.write('result', 'error' => nil)
      expect { described_class.write('result', 'error' => 'changed') }.to raise_error(/differs from Rails/)
    end
  end

  it 'normalizes import failure paths and backend frames with the shared fixture format' do
    gem = Gem.loaded_specs.fetch('i18n')
    prefix = "Import \"#{Rails.root.join('trace.zip')}\" failed: unknown format, Stacktrace: "
    frames = "#{Rails.root.join('app/services/imports/create.rb')}:35:in 'Imports::Create#call'\n" \
             "#{gem.full_gem_path}/lib/i18n.rb:383:in 'I18n.with_locale'\n" \
             "#{RbConfig::CONFIG.fetch('prefix')}/bin/bundle:25:in '<main>'"

    notification = described_class.portable_notification(prefix + frames)

    expect(notification).to eq(
      'Import "RAILS_ROOT/trace.zip" failed: unknown format, Stacktrace: ' \
      "RAILS_ROOT/app/services/imports/create.rb:LINE:in 'Imports::Create#call'\n" \
      "GEM_ROOT/i18n/lib/i18n.rb:LINE:in 'I18n.with_locale'\nRUBY_ROOT/bin/bundle:LINE:in '<main>'"
    )
    expect(notification).not_to include(Rails.root.to_s, gem.full_gem_path, RbConfig::CONFIG.fetch('prefix'))
  end
end
