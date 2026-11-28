# frozen_string_literal: true

# Cloud accounts due for retention deletion: the Privacy Policy keeps account
# data for up to 12 months after access ends. Access ends at `active_until`,
# or at signup for an account that never had a subscription. Nothing is
# deleted before LAUNCH_DATE. Returns users whose deletion date is within
# WARNING_HORIZON of `today` (or past), each carrying `computed_deletion_on`.
class Users::RetentionCandidatesQuery
  LAUNCH_DATE = Date.new(2027, 1, 1)
  WARNING_HORIZON = 30.days

  # Non-admin users whose access has ended, whenever that was.
  def self.access_ended
    User.where(admin: false)
        .where(
          'users.status IN (:ended) OR (users.status = :trial AND users.active_until < :now)',
          ended: [User.statuses[:inactive], User.statuses[:pending_payment]],
          trial: User.statuses[:trial],
          now: Time.current
        )
  end

  def initialize(today: Date.current)
    @today = today
  end

  def call
    self.class.access_ended
        .where("#{deletion_date_sql} <= ?", @today + WARNING_HORIZON)
        .select("users.*, #{deletion_date_sql} AS computed_deletion_on")
  end

  private

  def deletion_date_sql
    @deletion_date_sql ||= ActiveRecord::Base.sanitize_sql_array(
      [
        "GREATEST((COALESCE(users.active_until, users.created_at) + INTERVAL '12 months')::date, ?::date)",
        LAUNCH_DATE
      ]
    )
  end
end
