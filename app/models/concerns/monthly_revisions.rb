# frozen_string_literal: true

module MonthlyRevisions
  def for_user(user_id, start_at: nil, end_at: nil)
    scope = where(user_id: user_id)
    scope = scope.where(month: revision_month(start_at)..) if start_at
    scope = scope.where(month: ..revision_month(end_at)) if end_at
    Digest::SHA256.hexdigest(scope.order(:month).pluck(:month, :revision).to_json)
  end

  private

  def revision_month(timestamp)
    Time.at(timestamp).utc.to_date.beginning_of_month
  end
end
