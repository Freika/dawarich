defmodule Dawarich.Families.Expirations do
  @moduledoc false
  alias Dawarich.Families.{Clock, Sharing}

  def enqueue(repo, family, user, recipients, action, value, ctx) do
    boundaries = action_boundary(repo, user, action, value) ++ access_boundary(repo, family, ctx)

    for {kind, due} <- boundaries,
        not is_nil(due),
        NaiveDateTime.compare(due, DateTime.to_naive(ctx.now)) == :gt,
        id <- Enum.uniq(recipients) do
      event =
        Dawarich.AfterCommit.identity(
          id,
          "family-expiry:#{family}:#{kind}:#{NaiveDateTime.to_iso8601(due)}"
        )

      Dawarich.AfterCommit.enqueue(
        repo,
        Dawarich.Families.EventsWorker,
        %{"event_id" => event, "user_id" => id, "kind" => Atom.to_string(kind)},
        scheduled_at: DateTime.from_naive!(due, "Etc/UTC")
      )
    end

    :ok
  end

  defp action_boundary(_repo, _user, :set_sharing, config), do: consent(config)

  defp action_boundary(repo, user, :respond_location, %{"status" => "accepted"}) do
    [[settings]] = repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows
    consent(Sharing.config(settings))
  end

  defp action_boundary(repo, _user, :invite, id),
    do: row_boundary(repo, "family_invitations", id, :invitation)

  defp action_boundary(repo, _user, :request_location, %{"request" => %{"id" => id}}),
    do: row_boundary(repo, "family_location_requests", id, :request)

  defp action_boundary(_, _, _, _), do: []

  defp consent(%{"enabled" => true, "expires_at" => due}), do: [{:consent, Clock.parse(due)}]
  defp consent(_), do: []

  defp row_boundary(repo, table, id, kind) do
    case repo.query!("SELECT expires_at FROM #{table} WHERE id=$1", [id], log: false).rows do
      [[due]] -> [{kind, due}]
      [] -> []
    end
  end

  defp access_boundary(_repo, _family, %{self_hosted: true}), do: []

  defp access_boundary(repo, family, _ctx) do
    case repo.query!(
           "SELECT f.access_until,u.plan,u.active_until FROM families f LEFT JOIN users u ON u.id=f.creator_id AND u.deleted_at IS NULL WHERE f.id=$1",
           [family], log: false).rows do
      [[nil, 2, due]] -> [{:lapse, due}]
      [[due, _, _]] -> [{:lapse, due}]
      [] -> []
    end
  end
end
