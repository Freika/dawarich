defmodule Dawarich.Families.NativeDeadline do
  @moduledoc false
  alias Dawarich.Families.{Clock, NativeReads, WebCreate}

  def read(scope, opts) do
    with {:ok, user, ctx} <- NativeReads.actor(scope, opts),
         family when not is_nil(family) <- WebCreate.family(Dawarich.Repo, user.id) do
      {:ok, due(family.id, ctx)}
    else
      {:error, _} = error -> error
      _ -> {:error, :unauthorized}
    end
  end

  def due(family_id, ctx) do
    rows =
      Dawarich.Repo.query!(
        """
        SELECT u.settings #>> '{family,location_sharing,expires_at}'
        FROM users u JOIN family_memberships m ON m.user_id=u.id
        WHERE m.family_id=$1 AND u.deleted_at IS NULL
          AND u.settings #> '{family,location_sharing,enabled}' = 'true'::jsonb
        UNION ALL SELECT to_char(expires_at,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM family_invitations WHERE family_id=$1 AND status=0
        UNION ALL SELECT to_char(expires_at,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM family_location_requests WHERE family_id=$1 AND status=0
        """,
        [family_id],
        log: false
      ).rows

    access = if ctx.self_hosted, do: [], else: access(family_id)

    (List.flatten(rows) ++ access)
    |> Enum.map(&parse/1)
    |> Enum.reject(&(is_nil(&1) or NaiveDateTime.compare(&1, Clock.naive(ctx.now)) != :gt))
    |> Enum.min(NaiveDateTime, fn -> nil end)
  end

  defp parse(%NaiveDateTime{} = at), do: at
  defp parse(value), do: Clock.parse(value)

  defp access(family) do
    case Dawarich.Repo.query!(
           "SELECT f.access_until,u.plan,u.active_until FROM families f LEFT JOIN users u ON u.id=f.creator_id AND u.deleted_at IS NULL WHERE f.id=$1",
           [family],
           log: false
         ).rows do
      [[nil, 2, due]] -> [due]
      [[due, _, _]] -> [due]
      _ -> []
    end
  end
end
