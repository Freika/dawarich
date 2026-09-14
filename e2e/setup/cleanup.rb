# frozen_string_literal: true

ENV['E2E_SEED_SKIP_CALL'] = 'true'
load Rails.root.join('e2e/setup/seed.rb') unless defined?(TileOnlyMapE2ESeed)

TileOnlyMapE2ESeed.cleanup
FileUtils.rm_f(Rails.root.join('e2e/temp/seed.json'))
