defmodule Dawarich.AppVersion do
  @moduledoc false

  alias Dawarich.{Jobs, RailsSecret}

  def current,
    do:
      :dawarich
      |> Application.get_env(:app_version_file, ".app_version")
      |> File.read!()
      |> String.trim()

  def update_available?(now), do: update_available?(now, current())

  def update_available?(now, running_version) do
    if RailsSecret.rails_env(System.get_env()) == "production" do
      false
    else
      case Jobs.repo().query!(
             "SELECT latest_version FROM phoenix.app_version WHERE checked_at > $1",
             [
               DateTime.add(now, -6 * 3600)
             ]
           ) do
        %{rows: [[latest]]} -> newer?(latest, running_version)
        _ -> false
      end
    end
  end

  defp newer?(latest, running) do
    with {:ok, latest} <- Version.parse(latest), {:ok, running} <- Version.parse(running) do
      Version.compare(latest, running) == :gt
    else
      _ -> false
    end
  end
end
