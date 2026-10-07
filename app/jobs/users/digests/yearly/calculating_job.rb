# frozen_string_literal: true

class Users::Digests::Yearly::CalculatingJob < ApplicationJob
  queue_as :digests
  OWNER_KEY = 'command:digests.calculate_year'

  def perform(user_id, year, execution_receipt: nil)
    receipt = execution_receipt || Stats::EffectReceipts.id(job_id, 'digests.calculate_year', user_id, year.to_i)
    return if Users::Digests::Execution.published?('digests.calculate_year', user_id, year)
    return forward(user_id, year, execution_receipt) if JobOwnership.oban?(OWNER_KEY)

    Users::Digests::Execution.run(receipt, 'digests.calculate_year', user_id, year, source: job_id) do |step, error|
      if step == :publish
        publish(user_id, year)
      elsif step == :failed
        create_digest_failed_notification(user_id, error)
        :failed
      else
        calculate(user_id, year)
      end
    end
  end

  private

  def calculate(user_id, year)
    user = find_user_or_skip(user_id)
    return :missing unless user

    I18n.with_locale(user.locale) do
      recalculate_monthly_stats(user_id, year)
      Users::Digests::CalculateYear.new(user_id, year).call
    end
  rescue StandardError => e
    create_digest_failed_notification(user_id, e)
    :failed
  end

  def publish(user_id, year)
    Users::Digests::Commands.publish_email('year', user_id, year)
  rescue StandardError => e
    e
  end

  def forward(user_id, year, execution_receipt)
    payload = { 'user_id' => user_id, 'year' => year.to_i, 'time_zone' => Time.zone.name }
    payload['execution_receipt'] = execution_receipt if execution_receipt
    JobCommands.forward('digests.calculate_year', payload,
                        event_id: job_id, aggregate_id: user_id, producer: self.class.name)
  end

  def recalculate_monthly_stats(user_id, year)
    (1..12).each do |month|
      Stats::CalculateMonth.new(user_id, year, month).call
    end
  end

  BACKTRACE_LINE_LIMIT = 20

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    backtrace = error.backtrace&.first(BACKTRACE_LINE_LIMIT)&.join("\n")

    I18n.with_locale(user.locale) do
      period_label = I18n.t('jobs.users.digests.yearly.calculating_job.year_end_digest')
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.users.digests.yearly.calculating_job.period_label_calculation_failed', period_label:),
        content: I18n.t('jobs.users.digests.yearly.calculating_job.message_stacktrace_backtrace',
                        message: error.message, backtrace: backtrace)
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
