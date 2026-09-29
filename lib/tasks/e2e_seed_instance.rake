# frozen_string_literal: true

namespace :e2e do
  desc 'Load the seed data and the demo administrator the e2e suite assumes (idempotent)'
  task seed_instance: :environment do
    assert_safe_environment!

    Rails.application.load_seed
    Rails.cache.delete(Country::NAMES_TO_ISO_A2_CACHE_KEY)
    User.where(email: 'demo@dawarich.app').update_all(admin: true)
  end
end
