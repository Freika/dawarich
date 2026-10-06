defmodule Dawarich.Settings.Integrations do
  @moduledoc false
  alias Dawarich.{UserSettings, Settings.Integrations.Connection}
  alias Dawarich.Imports.Trek.{Endpoint, Client.Error}
  alias DawarichWeb.Translate

  @providers ~w(immich photoprism airtrail teslamate)
  @fields ~w(immich_url immich_api_key immich_skip_ssl_verification photoprism_url photoprism_api_key photoprism_skip_ssl_verification airtrail_url airtrail_api_key airtrail_skip_ssl_verification teslamate_url teslamate_username teslamate_password teslamate_api_token teslamate_skip_ssl_verification)

  def save(repo, id, params, opts \\ []) when is_map(params) do
    with [[%{} = previous]] <- read(repo, id),
         {:ok, changes} <- changes(params, previous),
         updated = Map.merge(UserSettings.safe(previous), changes),
         :ok <- validate(updated, opts) do
      {statuses, notices, alerts} = test_connections(previous, updated, opts)

      repo.transaction(fn ->
        case read(repo, id, " FOR UPDATE") do
          [[%{} = current]] ->
            settings = current |> Map.merge(changes) |> Map.merge(statuses) |> normalize_urls()

            repo.query!(
              "UPDATE users SET settings=$2,updated_at=$3 WHERE id=$1",
              [id, settings, NaiveDateTime.utc_now()],
              log: false
            )

            %{
              success: true,
              settings: settings,
              notices: [t(opts, "updated") | notices],
              alerts: alerts
            }

          _ ->
            repo.rollback(:invalid_settings)
        end
      end)
    else
      {:error, {:url, key, message}} ->
        {:ok,
         %{
           success: false,
           notices: [],
           alerts: [t(opts, "not_allowed", %{setting: humanize(key), message: message})]
         }}

      _ ->
        {:error, :invalid_settings}
    end
  rescue
    _ -> {:error, :save_failed}
  end

  defp read(repo, id, suffix \\ ""),
    do:
      repo.query!(
        "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL" <> suffix,
        [id],
        log: false
      ).rows

  defp changes(params, previous) do
    secrets =
      ~w(immich_api_key photoprism_api_key airtrail_api_key teslamate_password teslamate_api_token)

    changes =
      Map.take(params, @fields)
      |> Map.reject(fn {key, value} ->
        key in secrets and value == "********" and previous[key] not in [nil, ""]
      end)

    if Enum.any?(changes, fn {_, value} -> is_map(value) or is_list(value) end) do
      {:error, :invalid_settings}
    else
      changes =
        Map.new(changes, fn {key, value} ->
          {key,
           if(String.ends_with?(key, "_skip_ssl_verification"),
             do: UserSettings.cast(value),
             else: value
           )}
        end)

      changes =
        if Map.has_key?(changes, "teslamate_url") and
             changes["teslamate_url"] != previous["teslamate_url"] do
          Map.merge(changes, %{
            "teslamate_last_synced_at" => nil,
            "teslamate_last_synced_url" => nil,
            "teslamate_processing_pending" => false,
            "teslamate_processing_pending_url" => nil
          })
        else
          changes
        end

      {:ok, changes}
    end
  end

  defp validate(settings, opts) do
    Enum.reduce_while(@providers, :ok, fn provider, :ok ->
      key = provider <> "_url"

      if blank?(settings[key]) do
        {:cont, :ok}
      else
        try do
          Endpoint.resolve!(settings[key],
            self_hosted?: Keyword.fetch!(opts, :self_hosted),
            locale: Keyword.get(opts, :locale, "en")
          )

          {:cont, :ok}
        rescue
          error in Error ->
            message = String.replace_prefix(error.message, "TREK URL was rejected: ", "")
            {:halt, {:error, {:url, key, message}}}
        end
      end
    end)
  end

  defp test_connections(previous, updated, opts) do
    Enum.reduce(@providers, {%{}, [], []}, fn provider, {statuses, notices, alerts} = result ->
      keys = Enum.filter(@fields, &String.starts_with?(&1, provider <> "_"))

      if Enum.any?(keys, &(UserSettings.safe(previous)[&1] != updated[&1])) do
        case Connection.test(provider, updated, Keyword.get(opts, :locale, "en")) do
          {:ok, message} ->
            {Map.put(statuses, provider <> "_connection_status", "ok"), notices ++ [message],
             alerts}

          {:error, message} ->
            {Map.put(statuses, provider <> "_connection_status", "failed"), notices,
             alerts ++ [message]}
        end
      else
        result
      end
    end)
  end

  defp normalize_urls(settings) do
    Enum.reduce(~w(immich_url photoprism_url), settings, fn key, acc ->
      if is_binary(acc[key]),
        do: Map.update!(acc, key, &String.replace(&1, ~r{/+\z}, "")),
        else: acc
    end)
  end

  defp humanize(key), do: key |> String.replace("_", " ") |> String.capitalize()

  defp blank?(value),
    do: value in [nil, false, ""] or (is_binary(value) and String.trim(value) == "")

  defp t(opts, key, args \\ %{}),
    do: Translate.t(Keyword.get(opts, :locale, "en"), "services.settings.update." <> key, args)
end
