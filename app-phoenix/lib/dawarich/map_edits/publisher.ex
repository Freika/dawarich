defmodule Dawarich.MapEdits.Publisher do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def call(repo, actor, response) do
    gid = Base.encode64("gid://dawarich/User/#{actor}", padding: false)
    payload = %{"type" => "point_moved", "version" => 1, "data" => response}

    case Dawarich.Cable.Bus.publish(
           "map_edits:" <> gid,
           Ruby.json(payload) |> IO.iodata_to_binary(),
           repo: repo
         ) do
      {:error, _} -> Dawarich.Metrics.Map.post_commit_failure("broadcast")
      _ -> :ok
    end
  rescue
    _ -> Dawarich.Metrics.Map.post_commit_failure("broadcast")
  end
end
