defmodule Dawarich.NativeM5.Dependencies do
  @moduledoc false
  @derive {Inspect, only: [:actor_id, :locale]}
  defstruct [:actor_id, :locale, :identity]

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope

  def principal(%Scope{user: %{id: id} = user, locale: locale}),
    do: %__MODULE__{actor_id: id, locale: locale, identity: identity(user)}

  def principal(_), do: nil

  def admit(%__MODULE__{actor_id: id, identity: proof, locale: locale}) do
    with user when not is_nil(user) <- Accounts.get(id),
         current when is_binary(current) <- identity(user),
         true <- is_binary(proof) and Plug.Crypto.secure_compare(proof, current) do
      {:ok, Scope.for_user(user, locale)}
    else
      _ -> {:error, :stale_session}
    end
  end

  def admit(_), do: {:error, :stale_session}

  def request_point_export(scope, export, request_id, repo) do
    key = "native-points-export:#{scope.user.id}:#{request_id}"

    case repo.query!(
           "SELECT aggregate_id FROM public.job_outbox WHERE command_type='exports.points' AND dedupe_key=$1",
           [key],
           log: false
         ).rows do
      [[id]] ->
        {:ok, id}

      [] ->
        with {:ok, id} <- Dawarich.PointExports.create(export, scope.user, scope.locale, repo) do
          repo.query!(
            "UPDATE public.job_outbox SET dedupe_key=$1 WHERE command_type='exports.points' AND aggregate_id=$2",
            [key, id],
            log: false
          )

          {:ok, id}
        end
    end
  end

  def stats_upgrade_url(scope, now, hosted),
    do: DawarichWeb.StatsFormat.upgrade_url(scope.user, now, hosted, "data_window", "stats_index")

  def share_stat(scope, year, month, attrs, opts) do
    context = %{
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      locale: scope.locale,
      base_url: Keyword.get(opts, :base_url, ""),
      self_hosted: Keyword.get(opts, :self_hosted, true)
    }

    case Dawarich.Stats.Sharing.update(Dawarich.Repo, scope.user, year, month, attrs, context) do
      {:ok, result} ->
        {:ok,
         %{
           enabled: result.settings["enabled"],
           expires_at: result.settings["expires_at"],
           url: result.body["sharing_url"]
         }}

      other ->
        other
    end
  end

  defp identity(%{encrypted_password: hash}) when is_binary(hash) and byte_size(hash) >= 29,
    do: :crypto.hash(:sha256, String.slice(hash, 0, 29))

  defp identity(_), do: nil
end
