# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FixtureRecording do
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
      example.run
      expect(Rails.application.secret_key_base == secret).to be(true)
      expect(Rails.application.env_config.slice(*env.keys) == env).to be(true)
      expect(Turbo.signed_stream_verifier_key == turbo_key).to be(true)
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
  end
end
