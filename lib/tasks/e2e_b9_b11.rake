# frozen_string_literal: true

namespace :e2e do
  desc 'Seed isolated B9 notification characterization fixtures'
  task seed_b9_notifications: :environment do
    abort 'Refusing B9 fixture seeding in production' if Rails.env.production?

    demo = User.find_by!(email: 'demo@dawarich.app')
    other = User.find_or_create_by!(email: 'b9-other@dawarich.test') do |user|
      user.password = 'safepassword12'
      user.password_confirmation = 'safepassword12'
      user.admin = false
    end

    Notification.where(user: [demo, other]).where('title LIKE ?', 'B9 fixture%').delete_all

    1.upto(22) do |number|
      demo.notifications.create!(
        title: format('B9 fixture %02d', number),
        content: number == 22 ? 'B9 safe detail <script>window.b9Xss=true</script>' : "B9 safe detail #{number}",
        kind: number == 22 ? :error : :info,
        read_at: number <= 3 ? Time.current : nil,
        created_at: Time.current - number.minutes
      )
    end

    other.notifications.create!(title: 'B9 fixture other user', content: 'B9 other user only', kind: :info)
  end
end
