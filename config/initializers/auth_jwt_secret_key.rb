# frozen_string_literal: true

cloud_deploy = !(DawarichSettings.self_hosted? || Rails.env.development? || Rails.env.test?)
if cloud_deploy && ENV['AUTH_JWT_SECRET_KEY'].blank?
  raise 'AUTH_JWT_SECRET_KEY is required in cloud deploys. ' \
        'Mobile (iOS/Android) web sign-in mints a handoff token signed with it; ' \
        'a blank value makes JWT.encode raise and sign-in returns 500.'
end
