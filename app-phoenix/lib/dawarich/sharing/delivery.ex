defmodule Dawarich.Sharing.Delivery do
  @moduledoc false
  alias Dawarich.{Accounts, Repo, SharingExpiry}
  alias Dawarich.NativeM5.Dependencies
  alias Dawarich.SharedApi.Closure

  def admit(target, now, opts \\ []), do: admission(target, now, opts)

  def now(opts) do
    case option(opts, :clock, nil) do
      clock when is_function(clock, 0) -> clock.()
      _ -> option(opts, :now, nil) || DateTime.utc_now()
    end
  end

  def deliver(target, admitted, value, opts) do
    option(opts, :after_read, fn -> :ok end).()

    clock = option(opts, :clock, nil) || (&DateTime.utc_now/0)

    if not is_nil(admitted) and admission(target, clock.(), opts) == admitted,
      do: {:ok, value},
      else: {:error, :not_found}
  end

  def resource_snapshot({:ok, %{link: link, kind: kind}}),
    do: signature({link, kind, fingerprint(link.user_id)})

  def resource_snapshot(_), do: nil

  defp admission({:link, id, allowed}, now, _opts) do
    with link when not is_nil(link) <- Dawarich.SharedLinks.active(id, now),
         %Accounts.User{} = owner <- Accounts.public_owner(link.user_id),
         true <- allowed.(link, now) do
      signature(
        {link, Map.take(owner, [:id, :settings, :plan, :active_until]), fingerprint(link.user_id)}
      )
    else
      _ -> nil
    end
  end

  defp admission({:policy, allowed}, now, _opts) do
    if allowed.(now) == :ok, do: :ok
  end

  defp admission({:achievement, repo, uuid}, _now, _opts) do
    case repo.query!(
           "SELECT p.user_id,p.achievement_key,u.settings FROM achievement_progresses p JOIN users u ON u.id=p.user_id AND u.deleted_at IS NULL WHERE p.sharing_uuid=$1 AND p.sharing_enabled=true",
           [uuid],
           log: false,
           prepare: :unnamed
         ).rows do
      [] -> nil
      carrier -> carrier
    end
  end

  defp admission({kind, uuid, zone}, now, _opts) when kind in [:digest, :month] do
    table = if kind == :digest, do: "digests", else: "stats"

    with {:ok, value} <- Ecto.UUID.dump(uuid),
         [[id, owner_id, year, month, settings, revision]] <-
           Repo.query!(
             "SELECT id, user_id, year, month, sharing_settings, updated_at FROM #{table} WHERE sharing_uuid=$1 LIMIT 1",
             [value],
             log: false
           ).rows,
         true <- SharingExpiry.public?(settings, now, zone),
         %Accounts.User{} = owner <- Accounts.public_owner(owner_id) do
      signature(
        {id, owner_id, year, month, settings, revision,
         Map.take(owner, [:id, :settings, :plan, :active_until])}
      )
    else
      _ -> nil
    end
  end

  defp admission({:resource, grant}, now, opts),
    do: resource_snapshot(Dependencies.public_admit(grant, now, opts))

  defp fingerprint(owner),
    do:
      Closure.zones(owner)
      |> Enum.sort()
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))

  defp signature(value), do: value |> :erlang.term_to_binary() |> then(&:crypto.hash(:sha256, &1))

  defp option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)
  defp option(opts, key, default), do: Keyword.get(opts, key, default)
end
