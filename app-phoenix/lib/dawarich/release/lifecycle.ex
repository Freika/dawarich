defmodule Dawarich.Release.Lifecycle do
  @moduledoc false

  alias Dawarich.ReleaseMigration

  def mode(env \\ System.get_env())

  def mode(%{"DAWARICH_RAILS" => "off"} = env) do
    if ReleaseMigration.self_hosted?(env) or not cloud_configured?(env),
      do: native(env),
      else: flagged_mode(env)
  end

  def mode(env), do: flagged_mode(env)

  defp flagged_mode(env) do
    case Map.get(env, "DAWARICH_PHOENIX_LIFECYCLE", "false") do
      flag when flag in ["false", "true"] ->
        if flag == "true" or env["DAWARICH_RAILS"] == "off",
          do: native(env),
          else: {:ok, :rails}

      _ ->
        {:error, :invalid_lifecycle_flag}
    end
  end

  defp native(env) do
    cond do
      ReleaseMigration.self_hosted?(env) -> {:ok, :native}
      cloud_configured?(env) -> {:ok, :native}
      true -> {:error, :cloud_native_lifecycle}
    end
  end

  defp cloud_configured?(env) do
    env["SELF_HOSTED"] == "false" and
      env["DAWARICH_CLOUD_DRAIN_ONLY"] in [nil, "false"] and
      Dawarich.Cloud.Configuration.manager(env) == :ok and
      session_url?(env["DATABASE_SESSION_URL"])
  end

  defp session_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")
    config = Ecto.Repo.Supervisor.parse_url(url)

    uri.scheme in ["postgres", "postgresql"] and is_binary(uri.host) and uri.host != "" and
      uri.fragment == nil and config[:database] not in [nil, ""] and
      config[:port] != 6432 and
      Enum.all?(query, fn
        {"sslmode", value} -> value in ~w(disable require verify-ca verify-full)
        {"pool_mode", "session"} -> true
        {"pooling_mode", "session"} -> true
        _ -> false
      end)
  rescue
    _ -> false
  end

  defp session_url?(_), do: false
end
