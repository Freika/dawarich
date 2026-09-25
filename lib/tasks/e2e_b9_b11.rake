# frozen_string_literal: true

namespace :e2e do
  desc 'Seed isolated B9 notification characterization fixtures'
  task seed_b9_notifications: :environment do
    abort 'Refusing B9 fixture seeding in production' if Rails.env.production?

    reader = User.find_or_create_by!(email: 'b9-reader@dawarich.test') do |user|
      user.password = 'safepassword12'
      user.password_confirmation = 'safepassword12'
      user.admin = false
    end
    other = User.find_or_create_by!(email: 'b9-other@dawarich.test') do |user|
      user.password = 'safepassword12'
      user.password_confirmation = 'safepassword12'
      user.admin = false
    end

    Notification.where(user: [reader, other]).where('title LIKE ?', 'B9 fixture%').delete_all

    1.upto(22) do |number|
      reader.notifications.create!(
        title: format('B9 fixture %02d', number),
        content: number == 22 ? 'B9 safe detail <script>window.b9Xss=true</script>' : "B9 safe detail #{number}",
        kind: number == 22 ? :error : :info,
        read_at: number <= 3 ? Time.current : nil,
        created_at: Time.current - number.minutes
      )
    end

    other.notifications.create!(title: 'B9 fixture other user', content: 'B9 other user only', kind: :info)
  end

  desc 'Seed isolated B11 achievement characterization fixtures'
  task seed_b11_achievements: :environment do
    abort 'Refusing B11 fixture seeding in production' if Rails.env.production?

    user = User.find_by!(email: 'demo@dawarich.app')
    Flipper.enable(:achievements)

    progress = user.achievement_progresses.find_or_initialize_by(achievement_key: 'exploration')
    progress.update!(state: {
      'earned' => { 'DE' => '2026-07-01T10:00:00Z', 'DE-BY' => '2026-07-01T10:00:00Z' },
      'calculation_version' => Achievements::RegionSetChecker::CALCULATION_VERSION
    })

    carrier = user.achievement_progresses.find_by(achievement_key: 'country_de')
    carrier&.update!(sharing_enabled: false)

    unlock_user = User.find_or_create_by!(email: 'b11-unlock@dawarich.test') do |account|
      account.password = 'safepassword12'
      account.password_confirmation = 'safepassword12'
      account.admin = false
    end
    unlock_user.update_columns(
      changelog_consent: User.changelog_consents[:declined],
      settings: (unlock_user.settings || {}).merge('onboarding_completed' => true)
    )
    unlock_user.achievement_progresses.find_or_initialize_by(achievement_key: 'exploration').update!(
      state: { 'earned' => { 'DE' => '2026-07-01T10:00:00Z' } }
    )
    unlock_user.achievement_unlock_events.delete_all
    unlock_user.achievement_unlock_events.create!(kind: 'geography', key: 'DE')
  end
end
