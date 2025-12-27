# frozen_string_literal: true

class Users::DigestsMailerPreview < ActionMailer::Preview
  def year_end_digest
    user = User.first
    digest = user.digests.yearly.last || Users::Digest.last

    Users::DigestsMailer.with(user: user, digest: digest).year_end_digest
  end
end
