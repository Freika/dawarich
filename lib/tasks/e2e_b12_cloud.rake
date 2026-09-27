# frozen_string_literal: true

require 'fileutils'

module E2eB12Fixtures
  REGISTRATION_KEY = 'dawarich/registration_enabled'

  def self.verify!
    allowed = %w[dawarich_e2e_b12_cloud dawarich_e2e_b12_cloud_test]
    if Rails.env.production? || !allowed.include?(ENV['DATABASE_NAME'])
      abort('B12 fixtures require an isolated database')
    end
    abort('B12 egress guard is required') unless ENV['E2E_B12_EGRESS'] == '1'
  end

  def self.user(email, plan, admin)
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

  def self.write_output(payload)
    root = Rails.root.join('tmp/b12-fixtures')
    output = Pathname.new(ENV.fetch('B12_FIXTURE_OUTPUT'))
    unless output.dirname == root && output.basename.to_s.match?(/\A[a-z0-9-]+\.json\z/)
      abort('Invalid B12 fixture output path')
    end

    FileUtils.mkdir_p(root)
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(payload.to_json) }
  end
end

namespace :e2e do
  namespace :b12 do
    desc 'Create or return an isolated synthetic Cloud user'
    task :user, %i[email plan admin] => :environment do |_, args|
      E2eB12Fixtures.verify!
      user = E2eB12Fixtures.user(args[:email], args[:plan] || 'lite', args[:admin])
      payload = { id: user.id, email: user.email, api_key: user.api_key, plan: user.plan }
      E2eB12Fixtures.write_output(payload)
    end

    desc 'Issue a deletion link for one user while leaving another user active'
    task :deletion_pair, %i[first_email second_email] => :environment do |_, args|
      E2eB12Fixtures.verify!
      owner, other = args.values_at(:first_email, :second_email).map do |email|
        E2eB12Fixtures.user(email, 'lite', 'false')
      end
      token = Users::IssueDestroyToken.new(owner).call
      payload = { owner_id: owner.id, owner_api_key: owner.api_key,
                  other: { id: other.id, email: other.email, api_key: other.api_key },
                  link: "/users/me/destroy/confirm?token=#{token}" }
      E2eB12Fixtures.write_output(payload)
    end

    desc 'Create points on either side of the Lite calendar cutoff'
    task :lite_window, [:email] => :environment do |_, args|
      E2eB12Fixtures.verify!
      user = E2eB12Fixtures.user(args[:email], 'lite', 'false')
      cutoff = user.data_window_start
      ids = {}
      { inside: cutoff + 1.day, outside: cutoff - 1.day }.each do |side, at|
        point = user.points.find_or_create_by!(timestamp: at.to_i,
                                               lonlat: "POINT(#{side == :inside ? 12.37 : 12.38} 51.34)") do |item|
          item.reverse_geocoded_at = at
          item.tracker_id = 'b12-synthetic'
        end
        ids[side] = point.id
      end
      user.update_column(:points_count, user.points.count)
      payload = { id: user.id, api_key: user.api_key, inside_id: ids[:inside], outside_id: ids[:outside] }
      E2eB12Fixtures.write_output(payload)
    end

    desc 'Set the isolated Cloud registration switch'
    task :registration, [:enabled] => :environment do |_, args|
      E2eB12Fixtures.verify!
      if args[:enabled] == 'default'
        Rails.cache.delete(E2eB12Fixtures::REGISTRATION_KEY)
      else
        DawarichSettings.set_registration_enabled(args[:enabled] == 'true')
      end
      E2eB12Fixtures.write_output({ registration_enabled: Rails.cache.read(E2eB12Fixtures::REGISTRATION_KEY) })
    end

    desc 'Issue a one-use local trial welcome link'
    task :trial_welcome, [:email] => :environment do |_, args|
      E2eB12Fixtures.verify!
      user = E2eB12Fixtures.user(args[:email], 'lite', 'false')
      user.update_columns(status: User.statuses[:trial], active_until: 7.days.from_now,
                          signup_variant: 'reverse_trial')
      token = JWT.encode({ user_id: user.id, purpose: 'trial_welcome', jti: SecureRandom.uuid,
                           exp: 30.minutes.from_now.to_i }, ENV.fetch('JWT_SECRET_KEY'), 'HS256')
      E2eB12Fixtures.write_output({ link: "/trial/welcome?token=#{token}", email: user.email, api_key: user.api_key })
    end

    desc 'Issue a matching invitation for isolated API registration'
    task :family_invitation, %i[owner_email invitee_email] => :environment do |_, args|
      E2eB12Fixtures.verify!
      abort('B12 fixture email required') unless args[:invitee_email].to_s.match?(/\A[a-z0-9-]+@b12\.dawarich\.test\z/)
      owner = E2eB12Fixtures.user(args[:owner_email], 'family', 'false')
      Families::AutoCreate.new(user: owner).call unless owner.reload.in_family?
      invitation = Family::Invitation.create!(family: owner.reload.family, invited_by: owner,
                                              email: args[:invitee_email])
      E2eB12Fixtures.write_output({ invitation_token: invitation.token, owner_api_key: owner.api_key })
    end
  end
end
