defmodule Dawarich.SharedLinks.FamilyAudience do
  @moduledoc false

  alias Dawarich.{Entitlements, Repo, UserTimeZone}

  def family_only?(link), do: link.settings["audience"] == "family"

  def family_id(user_id, now, self_hosted \\ System.get_env("SELF_HOSTED") == "true") do
    case Repo.query!(
           "SELECT f.id, f.access_until, o.plan, o.active_until FROM family_memberships m JOIN families f ON f.id=m.family_id LEFT JOIN users o ON o.id=f.creator_id AND o.deleted_at IS NULL WHERE m.user_id=$1 ORDER BY m.id LIMIT 1",
           [user_id],
           log: false
         ).rows do
      [[id, until, plan, owner_until]] ->
        if self_hosted or Entitlements.inherited?(until, plan, owner_until, now), do: id

      [] ->
        nil
    end
  end

  def accessible?(link, viewer, now, self_hosted \\ System.get_env("SELF_HOSTED") == "true") do
    if family_only?(link) do
      with %{id: viewer_id} <- viewer,
           id when is_integer(id) <- family_id(link.user_id, now, self_hosted),
           true <- to_string(id) == to_string(link.settings["family_id"]),
           [[true]] <-
             Repo.query!(
               "SELECT EXISTS(SELECT 1 FROM family_memberships WHERE family_id=$1 AND user_id=$2)",
               [id, viewer_id],
               log: false
             ).rows do
        true
      else
        _ -> false
      end
    else
      true
    end
  end

  def trips(user, page, now) do
    case family_id(user.id, now) do
      nil ->
        %{entries: [], total_pages: 0}

      family ->
        rows =
          Repo.query!(
            "SELECT t.name,t.started_at,t.ended_at,s.id::text,count(*) OVER() FROM trips t JOIN shared_links s ON s.resource_id=t.id AND s.user_id=t.user_id JOIN users u ON u.id=s.user_id AND u.deleted_at IS NULL JOIN family_memberships m ON m.user_id=u.id WHERE m.family_id=$1 AND s.user_id<>$2 AND s.resource_type=0 AND s.settings->>'audience'='family' AND s.settings->>'family_id'=$1::text AND s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at>$3) ORDER BY t.started_at DESC,t.id LIMIT 6 OFFSET $4",
            [family, user.id, DateTime.to_naive(now), (page - 1) * 6],
            log: false
          ).rows

        entries =
          Enum.map(rows, fn [name, started, ended, share, _] ->
            %{
              name: name,
              share_id: share,
              started_on:
                UserTimeZone.local(Dawarich.UserSettings.get(user), started).local
                |> NaiveDateTime.to_date(),
              ended_on:
                UserTimeZone.local(Dawarich.UserSettings.get(user), ended).local
                |> NaiveDateTime.to_date()
            }
          end)

        total =
          case rows do
            [] -> 0
            [row | _] -> div(List.last(row) + 5, 6)
          end

        %{entries: entries, total_pages: total}
    end
  end
end
