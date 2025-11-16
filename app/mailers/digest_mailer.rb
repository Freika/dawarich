# frozen_string_literal: true

class DigestMailer < ApplicationMailer
  def monthly_digest(user, year, month)
    @user = user
    @year = year
    @month = month
    @period_type = :monthly
    @digest_data = Digests::Calculator.new(user, period: :monthly, year: year, month: month).call

    return if @digest_data.nil?  # Don't send if calculation failed

    mail(
      to: user.email,
      subject: "#{Date::MONTHNAMES[month]} #{year} - Your Location Recap"
    )
  end

  # Future: yearly_digest method
  # def yearly_digest(user, year)
  #   @user = user
  #   @year = year
  #   @period_type = :yearly
  #   @digest_data = Digests::Calculator.new(user, period: :yearly, year: year).call
  #
  #   mail(
  #     to: user.email,
  #     subject: "#{year} Year in Review - Your Location Recap"
  #   )
  # end
end
