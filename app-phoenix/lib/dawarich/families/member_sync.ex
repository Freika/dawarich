defmodule Dawarich.Families.MemberSync do
  @moduledoc false

  alias Dawarich.Families.{LapseNotices, MemberEntitlements}
  alias Dawarich.Jobs.Ownership
  alias DawarichWeb.LayoutAssigns

  def run(repo, family_id, opts \\ []) do
    if LayoutAssigns.self_hosted?() do
      false
    else
      {:ok, result} = repo.transaction(fn -> sync(repo, family_id, opts) end)
      result
    end
  end

  defp sync(repo, family_id, opts) do
    mail_owner = Ownership.lock(repo, "command:mail.family_lapse")

    case repo.query!(
           "SELECT creator_id, access_until FROM families WHERE id = $1 FOR UPDATE",
           [family_id],
           log: false
         ).rows do
      [[creator_id, access_until]] ->
        owner =
          repo.query!(
            "SELECT plan, active_until FROM users WHERE id = $1 AND deleted_at IS NULL",
            [creator_id],
            log: false
          ).rows

        period = period(owner, access_until)
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        at = DateTime.to_naive(now)

        if period != access_until,
          do:
            repo.query!(
              "UPDATE families SET access_until = $2, updated_at = $3 WHERE id = $1",
              [family_id, period, at],
              log: false
            )

        members =
          repo.query!(
            "SELECT u.id, u.plan, u.status, u.active_until, u.subscription_source, u.settings " <>
              "FROM users u JOIN family_memberships m ON m.user_id = u.id " <>
              "WHERE m.family_id = $1 AND u.deleted_at IS NULL AND u.id <> $2 ORDER BY u.id FOR UPDATE OF u",
            [family_id, creator_id],
            log: false
          ).rows

        for member <- members do
          MemberEntitlements.sync(repo, member, period, now, fn user_id, settings ->
            LapseNotices.lapse(repo, user_id, family_id, settings, period, now, mail_owner, opts)
          end)

          Keyword.get(opts, :hook, fn _ -> :ok end).(hd(member))
        end

        true

      [] ->
        false
    end
  end

  defp period([], access_until), do: access_until
  defp period([[_plan, nil]], access_until), do: access_until
  defp period([[2, owner_until]], _access_until), do: owner_until
  defp period([[_plan, _until]], nil), do: nil

  defp period([[_plan, owner_until]], access_until),
    do: Enum.min([access_until, owner_until], NaiveDateTime)
end
