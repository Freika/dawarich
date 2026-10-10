defmodule Dawarich.NativeM5.Dependencies do
  @moduledoc false
  def stats_upgrade_url(scope, now, hosted),
    do: DawarichWeb.StatsFormat.upgrade_url(scope.user, now, hosted, "data_window", "stats_index")

  def insights_upgrade_url(scope, now, hosted),
    do: DawarichWeb.StatsFormat.upgrade_url(scope.user, now, hosted, "data_window", "insights")

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
           expiration: result.settings["expiration"] || "24h",
           expires_at: result.settings["expires_at"],
           url: result.body["sharing_url"]
         }}

      other ->
        other
    end
  end

  def stat_sharing(scope, year, month, opts) do
    with {:ok, fresh} <- Dawarich.Accounts.DataAccess.admit(scope),
         [[settings, uuid]] <-
           Dawarich.Repo.query!(
             "SELECT sharing_settings,sharing_uuid::text FROM stats WHERE user_id=$1 AND year=$2 AND month=$3 LIMIT 1",
             [fresh.user.id, year, month],
             log: false
           ).rows do
      settings = settings || %{}
      enabled = settings["enabled"] == true

      url =
        if enabled and is_binary(uuid),
          do: Keyword.get(opts, :base_url, "") <> "/shared/month/" <> uuid,
          else: ""

      {:ok, %{enabled: enabled, expiration: settings["expiration"] || "24h", url: url}}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def digest_upgrade_url(scope, now, hosted),
    do: DawarichWeb.StatsFormat.upgrade_url(scope.user, now, hosted, "digest", "year_in_review")

  def share_digest(scope, year, attrs, opts) do
    context = %{
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      locale: scope.locale,
      base_url: Keyword.get(opts, :base_url, ""),
      self_hosted: Keyword.get(opts, :self_hosted, true)
    }

    case Dawarich.Digests.Sharing.update(Dawarich.Repo, scope.user, year, attrs, context) do
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

  def digest_sharing(scope, year, opts) do
    with {:ok, fresh} <- Dawarich.Accounts.DataAccess.admit(scope),
         [[settings, uuid]] <-
           Dawarich.Repo.query!(
             "SELECT sharing_settings,sharing_uuid::text FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1 LIMIT 1",
             [fresh.user.id, year],
             log: false
           ).rows do
      settings = settings || %{}
      enabled = settings["enabled"] == true

      url =
        if enabled and is_binary(uuid),
          do: Keyword.get(opts, :base_url, "") <> "/shared/digest/" <> uuid,
          else: ""

      {:ok, %{enabled: enabled, expiration: settings["expiration"] || "24h", url: url}}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def public_admit(grant, now, opts \\ []) do
    module = Keyword.get(opts, :admission, Dawarich.Sharing.Public)

    if Code.ensure_loaded?(module),
      do: apply(module, :admit, [grant, now]),
      else: {:error, :unavailable}
  end

  def public_photos(link), do: Dawarich.SharedApi.Photos.response(link, :photos)

  def public_description(body) do
    if Code.ensure_loaded?(Dawarich.Trips.Description),
      do: apply(Dawarich.Trips.Description, :render, [body]),
      else: Dawarich.Trips.RichContent.read(body)
  end
end
