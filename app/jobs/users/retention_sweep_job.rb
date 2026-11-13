# frozen_string_literal: true

# Deletes Cloud accounts 12 months after their access ended, as the Privacy
# Policy promises, after warning emails 30, 7 and 1 day before.
#
# The first warning fixes the date promised to the user in
# settings['retention']['deletion_on'], never less than 30 days away, so a
# missed run or a late deploy still gives a full notice period. If the
# computed date changes (the user resubscribed and lapsed again), the state
# starts over.
class Users::RetentionSweepJob < ApplicationJob
  queue_as :archival

  WARNING_STAGES = { '30d' => 30, '7d' => 7, '1d' => 1 }.freeze
  NOTICE_PERIOD = 30.days

  def perform
    return if DawarichSettings.self_hosted?

    today = Date.current
    outcomes = Hash.new(0)
    forget_accounts_with_access

    Users::RetentionCandidatesQuery.new(today:).call.find_each do |user|
      outcomes[sweep(user, today)] += 1
    rescue StandardError => e
      ExceptionReporter.call(e, "#{self.class.name} failed for user_id=#{user.id}")
      outcomes[:failed] += 1
    end

    Rails.logger.info("[#{self.class.name}] #{outcomes.map { |outcome, count| "#{outcome}=#{count}" }.join(' ')}")
  end

  private

  def sweep(user, today)
    return skip_family_owner(user) unless user.can_delete_account?

    computed_on = user.computed_deletion_on
    state = retention_state(user, computed_on)
    promised_on = state['deletion_on'] && Date.iso8601(state['deletion_on'])

    return delete(user) if promised_on && today >= promised_on

    warn(user, state, computed_on, promised_on || [computed_on, today + NOTICE_PERIOD].max, today)
  end

  def warn(user, state, computed_on, deletion_on, today)
    sent = state['sent'] || {}
    due = WARNING_STAGES.select { |key, days| today >= deletion_on - days && sent[key].blank? }
    return :waiting if due.empty?

    Users::MailerSendingJob.perform_later(user.id, 'account_deletion_warning', deletion_on: deletion_on.iso8601)
    save_state(
      user,
      'computed_on' => computed_on.iso8601,
      'deletion_on' => deletion_on.iso8601,
      'sent' => sent.merge(due.keys.index_with { today.iso8601 })
    )

    :"warned_#{due.min_by { |_key, days| days }.first}"
  end

  # The UPDATE re-checks that access is still over, so a user who resubscribed
  # after this run loaded them is never deleted.
  def delete(user)
    marked = Users::RetentionCandidatesQuery.access_ended.where(id: user.id).update_all(deleted_at: Time.current)
    return :access_restored if marked.zero?

    Users::DestroyJob.set(queue: :archival).perform_later(user.id)
    :deleted
  end

  # A family owner cannot be deleted while members remain, so they get no
  # warning for a date that would not hold. Once the members are gone, the
  # sweep starts over with a full notice period.
  def skip_family_owner(user)
    User.where(id: user.id).where("users.settings ? 'retention'").update_all("settings = settings - 'retention'")
    :skipped_family_owner
  end

  # An account whose access came back loses its schedule, so a later lapse
  # starts with fresh warnings even if it lands on the same computed date.
  def forget_accounts_with_access
    User.where("users.settings ? 'retention'")
        .where.not(id: Users::RetentionCandidatesQuery.access_ended.select(:id))
        .update_all("settings = settings - 'retention'")
  end

  def retention_state(user, computed_on)
    state = user.settings.is_a?(Hash) ? user.settings['retention'] : nil
    return {} unless state.is_a?(Hash) && state['computed_on'] == computed_on.iso8601

    state
  end

  # Writes only the retention key, so a concurrent settings change survives.
  def save_state(user, state)
    User.where(id: user.id).update_all(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "settings = jsonb_set(CASE WHEN jsonb_typeof(settings) = 'object' THEN settings ELSE '{}'::jsonb END, " \
          "'{retention}', ?::jsonb)",
          state.to_json
        ]
      )
    )
  end
end
