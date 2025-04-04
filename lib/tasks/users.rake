# frozen_string_literal: true

namespace :users do
  desc 'Activate all users'
  task activate: :environment do
    unless DawarichSettings.self_hosted?
      puts 'This task is only available for self-hosted users'
      exit 1
    end

    puts 'Activating all users...'
    # rubocop:disable Rails/SkipsModelValidations
    User.update_all(status: :active)
    # rubocop:enable Rails/SkipsModelValidations

    puts 'All users have been activated'
  end
end
