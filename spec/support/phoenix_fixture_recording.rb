# frozen_string_literal: true

require_relative '../../app-phoenix/scripts/parity/fixture_recording'

RSpec.configure do |config|
  config.include FixtureRecording::CanonicalTimezone,
                 file_path: %r{/app-phoenix/scripts/parity/.*_(?:fixtures|golden)_spec\.rb\z}
  frames = %r{/app-phoenix/scripts/parity/map_frames_fixtures_spec\.rb\z}
  config.define_derived_metadata(file_path: frames) do |metadata|
    if metadata[:description].match?(/writes A8 review missing_timezone_(?:midnight|dst) from Rails/)
      metadata[:fixture_timezone] = 'Europe/Berlin'
    end
  end
  config.include FixtureRecording::SyntheticSecret,
                 file_path: %r{/app-phoenix/scripts/parity/.*_fixtures_spec\.rb\z}
end
