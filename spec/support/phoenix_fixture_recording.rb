# frozen_string_literal: true

require_relative '../../app-phoenix/scripts/parity/fixture_recording'

RSpec.configure do |config|
  config.include FixtureRecording::SyntheticSecret,
                 file_path: %r{/app-phoenix/scripts/parity/.*_fixtures_spec\.rb\z}
end
