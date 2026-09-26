# frozen_string_literal: true

namespace :e2e do
  namespace :b12 do
    def assert_b12_database!
      allowed = %w[dawarich_e2e_b12_cloud dawarich_e2e_b12_cloud_test]
      if Rails.env.production? || !allowed.include?(ENV['DATABASE_NAME'])
        abort('B12 fixtures require an isolated database')
      end
      abort('B12 egress guard is required') unless ENV['E2E_B12_EGRESS'] == '1'
    end

    def b12_user(email, plan, admin)
      abort('B12 fixture email required') unless email.to_s.match?(/\A[a-z0-9-]+@b12\.dawarich\.test\z/)
      abort('Invalid B12 plan') unless %w[lite pro family].include?(plan)

      user = User.find_or_initialize_by(email: email)
      if user.new_record?
        user.password = 'safepassword12'
        user.password_confirmation = 'safepassword12'
        user.settings = { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true }
        user.save!
      end
      user.update_columns(
        status: User.statuses[:active],
        plan: User.plans.fetch(plan),
        active_until: plan == 'lite' ? nil : 30.days.from_now,
        subscription_source: plan == 'lite' ? User.subscription_sources[:none] : User.subscription_sources[:paddle],
        admin: admin == 'true',
        changelog_consent: User.changelog_consents[:declined]
      )
      user.reload
    end

    desc 'Create or return an isolated synthetic Cloud user'
    task :user, %i[email plan admin] => :environment do |_, args|
      assert_b12_database!
      user = b12_user(args[:email], args[:plan] || 'lite', args[:admin])
      payload = { id: user.id, email: user.email, api_key: user.api_key, plan: user.plan }
      puts "B12_FIXTURE=#{payload.to_json}"
    end

    desc 'Create points on either side of the Lite calendar cutoff'
    task :lite_window, [:email] => :environment do |_, args|
      assert_b12_database!
      user = b12_user(args[:email], 'lite', 'false')
      cutoff = user.data_window_start
      ids = {}
      { inside: cutoff + 1.day, outside: cutoff - 1.day }.each do |side, at|
        point = user.points.find_or_create_by!(timestamp: at.to_i,
                                               lonlat: "POINT(#{side == :inside ? 13.4 : 13.5} 52.5)") do |item|
          item.reverse_geocoded_at = at
          item.tracker_id = 'b12-synthetic'
        end
        ids[side] = point.id
      end
      user.update_column(:points_count, user.points.count)
      payload = { id: user.id, api_key: user.api_key, inside_id: ids[:inside], outside_id: ids[:outside] }
      puts "B12_FIXTURE=#{payload.to_json}"
    end

    desc 'Set the isolated Cloud registration switch'
    task :registration, [:enabled] => :environment do |_, args|
      assert_b12_database!
      enabled = args[:enabled] == 'true'
      DawarichSettings.set_registration_enabled(enabled)
      payload = { registration_enabled: enabled }
      puts "B12_FIXTURE=#{payload.to_json}"
    end
  end
end
