defmodule Dawarich.Families.MemberEntitlements do
  @moduledoc false

  alias Dawarich.Entitlements
  alias Dawarich.Families.LapseNotices

  def sync(repo, [id, _plan, status, active_until, source, settings], period, now, lapse) do
    unless source != 0 and status in [1, 2] and Entitlements.future?(active_until, now) do
      if Entitlements.future?(period, now) do
        repo.query!(
          "UPDATE users SET plan = 1, status = 1, active_until = $2, subscription_source = 0, updated_at = $3 WHERE id = $1",
          [id, period, DateTime.to_naive(now)],
          log: false
        )

        LapseNotices.clear(repo, id, settings, now)
      else
        repo.query!(
          "UPDATE users SET plan = 0, status = 0, active_until = $2, updated_at = $3 WHERE id = $1",
          [id, period, DateTime.to_naive(now)],
          log: false
        )

        lapse.(id, settings)
      end
    end
  end
end
