# frozen_string_literal: true

class Users::Digests::Monthly::CalculatingJob < ApplicationJob
  queue_as :digests
  OWNER_KEY = 'command:digests.calculate_month'

  def perform(user_id, year, month, execution_receipt: nil)
    receipt = execution_receipt || Stats::EffectReceipts.id(job_id, 'digests.calculate_month', user_id, year.to_i,
                                                            month.to_i)
    return if Stats::EffectReceipts.done?(receipt)
    return forward(user_id, year, month, execution_receipt) if JobOwnership.oban?(OWNER_KEY)

    Stats::EffectReceipts.once(receipt, 'digests.calculate_month') do
      calculate(user_id, year, month)
    end
  end

  private

  def calculate(user_id, year, month)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      Stats::CalculateMonth.new(user_id, year, month).call
      Users::Digests::CalculateMonth.new(user_id, year, month).call

      Users::Digests::Commands.publish_email('month', user_id, year, month: month)
    end
  rescue StandardError => e
    create_digest_failed_notification(user_id, e)
    :failed
  end

  def forward(user_id, year, month, execution_receipt)
    payload = { 'user_id' => user_id, 'year' => year.to_i, 'month' => month.to_i, 'time_zone' => Time.zone.name }
    payload['execution_receipt'] = execution_receipt if execution_receipt
    JobCommands.forward('digests.calculate_month', payload,
                        event_id: job_id, aggregate_id: user_id, producer: self.class.name)
  end

  BACKTRACE_LINE_LIMIT = 20

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    backtrace = error.backtrace&.first(BACKTRACE_LINE_LIMIT)&.join("\n")

    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.users.digests.monthly.calculating_job.monthly_digest_calculation_failed'),
        content: I18n.t('jobs.users.digests.monthly.calculating_job.message_stacktrace_backtrace',
                        message: error.message, backtrace: backtrace)
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
