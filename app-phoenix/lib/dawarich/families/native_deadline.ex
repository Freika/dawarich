defmodule Dawarich.Families.NativeDeadline do
  @moduledoc false
  alias Dawarich.Families.{Clock, NativeReads, WebCreate}

  def read(scope, opts) do
    with {:ok, user, ctx} <- NativeReads.actor(scope, opts),
         family when not is_nil(family) <- WebCreate.family(Dawarich.Repo, user.id) do
      {:ok, due(family, user, ctx)}
    else
      {:error, _} = error -> error
      _ -> {:error, :unauthorized}
    end
  end

  def due(family, user, ctx) do
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
        [family.id],
        log: false
      ).rows

    access = Dawarich.FamilyPageAccess.deadline(user, family, ctx.self_hosted, ctx.now)

    (List.flatten(rows) ++ [access])
    |> Enum.map(&parse/1)
    |> Enum.reject(&(is_nil(&1) or NaiveDateTime.compare(&1, Clock.naive(ctx.now)) != :gt))
    |> Enum.min(NaiveDateTime, fn -> nil end)
  end

  defp parse(%DateTime{} = at), do: DateTime.to_naive(at)
  defp parse(%NaiveDateTime{} = at), do: at
  defp parse(value), do: Clock.parse(value)
end
