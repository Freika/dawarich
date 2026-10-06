defmodule Dawarich.Jobs.Cron do
  @moduledoc false

  def timezone(env \\ System.get_env()) do
    if Dawarich.Standalone.enabled?(env) do
      case env["TZ"] do
        zone when is_binary(zone) and zone != "" ->
          case DateTime.now(zone) do
            {:ok, _} -> zone
            {:error, _} -> default_zone(env)
          end

        _ ->
          default_zone(env)
      end
    else
      "Etc/UTC"
    end
  end

  defp default_zone(env),
    do: Dawarich.TimeZoneName.to_iana(env["TIME_ZONE"] || "Europe/Berlin")
end
