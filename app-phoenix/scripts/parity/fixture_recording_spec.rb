# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FixtureRecording do
  it 'records canonical IANA country latitudes independently of the ambient tzdata source' do
    source = TZInfo::DataSources::RubyDataSource.new
    expected = source.country_codes.each_with_object({}) do |code, latitudes|
      source.get_country_info(code).zones.each do |zone|
        latitudes[zone.identifier] ||= zone.latitude.to_f
      end
    end
    allow(TZInfo::Country).to receive(:all).and_raise('ambient tzdata must not supply recording inputs')

    expect(described_class.canonical_timezone_latitudes).to eq(expected)
    expect(expected.keys - source.data_timezone_identifiers).to be_empty
    expect(expected.fetch('Australia/Sydney')).to be_negative
    expect(expected.fetch('Europe/Berlin')).to be_positive
    expect(expected).not_to have_key('Australia/NSW')
  end

  it 'normalizes diagnostic paths and stack lines while preserving visible error text' do
    gem = Gem.loaded_specs.fetch('actionpack')
    diagnostic = { 'error' => ["Missing template in #{Rails.root.join('app/views')}",
                               "#{gem.full_gem_path}/lib/example.rb:123:in 'call'",
                               "#{Rails.root.join('spec/example.rb')}:456:in 'capture'",
                               "#{RbConfig::CONFIG.fetch('prefix')}/bin/rspec:25:in 'load'",
                               '<div>Extracted source (around line <strong>#123</strong>):</div>' \
                               '<pre class="line_numbers"><span>123</span></pre>',
                               'Bad <b>waypoint</b> & more, HTTP 422, 12:34'] }
    expect(described_class.normalize(diagnostic)).to eq(
      'error' => ['Missing template in RAILS_ROOT/app/views', "GEM_ROOT/actionpack/lib/example.rb:LINE:in 'call'",
                  "RAILS_ROOT/spec/example.rb:LINE:in 'capture'", "RUBY_ROOT/bin/rspec:LINE:in 'load'",
                  '<div>Extracted source (around line <strong>#LINE</strong>):</div>' \
                  '<pre class="line_numbers"><span>LINE</span></pre>', 'Bad <b>waypoint</b> & more, HTTP 422, 12:34']
    )
  end

  context 'with the fixture secret' do
    around do |example|
      secret = Rails.application.secret_key_base
      env = Rails.application.env_config.slice('action_dispatch.secret_key_base', 'action_dispatch.key_generator')
      turbo_key = Turbo.signed_stream_verifier_key
      factory = Rails.application.message_verifiers
      storage = ActiveStorage.verifier
      blob = ActiveStorage::Blob.signed_id_verifier
      global_id = SignedGlobalID.verifier
      configured_global_id = Rails.application.config.global_id.verifier
      example.run
      expect(Rails.application.secret_key_base == secret).to be(true)
      expect(Rails.application.env_config.slice(*env.keys) == env).to be(true)
      expect(Turbo.signed_stream_verifier_key == turbo_key).to be(true)
      expect(Rails.application.message_verifiers).to equal(factory)
      expect(ActiveStorage.verifier).to equal(storage)
      expect(ActiveStorage::Blob.signed_id_verifier).to equal(blob)
      expect(SignedGlobalID.verifier).to equal(global_id)
      expect(Rails.application.config.global_id.verifier).to equal(configured_global_id)
    end

    include FixtureRecording::SyntheticSecret

    it 'pins the application cookies and Turbo signer to the synthetic fixture key' do
      expect(Rails.application.secret_key_base).to eq(described_class::SECRET)
      expect(Rails.application.env_config.fetch('action_dispatch.secret_key_base')).to eq(described_class::SECRET)
      expect(Rails.application.env_config.fetch('action_dispatch.key_generator'))
        .to equal(Rails.application.key_generator)
      expect(Turbo.signed_stream_verifier_key)
        .to eq(Rails.application.key_generator.generate_key('turbo/signed_stream_verifier_key'))
    end

    it 'rebuilds initialized storage and GlobalID verifiers from the synthetic key and restores them' do
      storage = ActiveSupport::MessageVerifiers.new do |salt|
        Rails.application.key_generator.generate_key(salt)
      end.rotate_defaults['ActiveStorage']
      global_id = GlobalID::Verifier.new(Rails.application.key_generator.generate_key('signed_global_ids'))
      token = storage.generate(42, purpose: :blob_id)
      expect(ActiveStorage.verifier.verified(token, purpose: :blob_id)).to eq(42)
      expect(ActiveStorage::Blob.signed_id_verifier.verified(token, purpose: :blob_id)).to eq(42)
      token = global_id.generate('gid://dawarich/ActiveStorage::Blob/42', purpose: 'attachable')
      expect(SignedGlobalID.verifier.verified(token, purpose: 'attachable')).to eq('gid://dawarich/ActiveStorage::Blob/42')
      expect(Rails.application.config.global_id.verifier).to equal(SignedGlobalID.verifier)
    end
  end

  context 'with the recording timezone' do
    around do |example|
      previous = ENV.fetch('TIME_ZONE', nil)
      zone = Time.zone
      ENV['TIME_ZONE'] = 'Pacific/Honolulu'
      example.run
      expect(ENV.fetch('TIME_ZONE')).to eq('Pacific/Honolulu')
      expect(Time.zone).to equal(zone)
    ensure
      previous.nil? ? ENV.delete('TIME_ZONE') : ENV['TIME_ZONE'] = previous
    end

    include FixtureRecording::CanonicalTimezone
    before(:context) { @recording_context_timezone = ENV.fetch('TIME_ZONE', nil) }

    it 'pins the Rails recording zone and context independently of the boot environment' do
      expect(Time.zone.tzinfo.name).to eq('Europe/Berlin')
      expect(@recording_context_timezone).to be_nil
    end

    it 'pins unset recording timezone and UTC defaults while restoring the ambient environment' do
      expect(ENV.fetch('TIME_ZONE', nil)).to be_nil
      expect(Users::SafeSettings.new({}).timezone).to eq('UTC')
    end

    it 'pins the Berlin default for recordings that require it', fixture_timezone: 'Europe/Berlin' do
      expect(ENV.fetch('TIME_ZONE', nil)).to be_nil
      expect(Users::SafeSettings.new({}).timezone).to eq('Europe/Berlin')
    end
  end
  it 'records minified source packets without replacing the domain packet' do
    Dir.mktmpdir do |root|
      domain = File.join(root, 'test/fixtures/map_frames/a12f3a-m01.json')
      source = File.join(root, 'test/fixtures/a12f3a_source/map_frames/a12f3a-m01.json')
      FileUtils.mkdir_p(File.dirname(domain))
      File.write(domain, '{"domain":true}')
      previous = ENV['WRITE_PHOENIX_FIXTURES']
      ENV['WRITE_PHOENIX_FIXTURES'] = '1'
      described_class.source_verify(domain, JSON.pretty_generate({ source: ['body', { status: 200 }] }))
      expect(File.read(domain)).to eq('{"domain":true}')
      expect(File.read(source)).to eq("{\"source\":[\"body\",{\"status\":200}]}\n")
      ENV.delete('WRITE_PHOENIX_FIXTURES')
      described_class.source_verify(domain, JSON.pretty_generate({ source: ['body', { status: 200 }] }))
    ensure
      previous.nil? ? ENV.delete('WRITE_PHOENIX_FIXTURES') : ENV['WRITE_PHOENIX_FIXTURES'] = previous
    end
  end
end
