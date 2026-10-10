defmodule Dawarich.Sharing.Delivery do
  @moduledoc false
  alias Dawarich.{Accounts, Repo, SharingExpiry}
  alias Dawarich.NativeM5.Dependencies
  alias Dawarich.SharedApi.Closure

  def admit(target, now, opts \\ []), do: admission(target, now, opts)

  def deliver(target, admitted, value, opts) do
    option(opts, :after_read, fn -> :ok end).()

    clock = option(opts, :clock, nil) || (&DateTime.utc_now/0)

    if not is_nil(admitted) and admission(target, clock.(), opts) == admitted,
      do: {:ok, value},
      else: {:error, :not_found}
  end

  def resource_snapshot({:ok, %{link: link, kind: kind}}),
    do: {link, kind, fingerprint(link.user_id)}

  def resource_snapshot(_), do: nil

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
         [[owner_id, settings]] <-
           Repo.query!(
             "SELECT user_id, sharing_settings FROM #{table} WHERE sharing_uuid=$1 LIMIT 1",
             [value],
             log: false
           ).rows,
         true <- SharingExpiry.public?(settings, now, zone),
         %Accounts.User{} = owner <- Accounts.public_owner(owner_id) do
      {owner_id, settings, owner}
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

  defp option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)
  defp option(opts, key, default), do: Keyword.get(opts, key, default)
end
