# frozen_string_literal: true

class Users::DigestsMailerPreview < ActionMailer::Preview
  def year_end_digest
    digest = Users::Digest.yearly.last
    Users::DigestsMailer.with(user: digest.user, digest: digest).year_end_digest
  end

  def monthly_digest
    digest = Users::Digest.monthly.last
    Users::DigestsMailer.with(user: digest.user, digest: digest).monthly_digest
  end
end
