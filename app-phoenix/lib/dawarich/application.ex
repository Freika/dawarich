defmodule Dawarich.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [Dawarich.Repo, {Oban, Application.fetch_env!(:dawarich, Oban)}] ++ rails_server()

    Supervisor.start_link(children, strategy: :one_for_one, name: Dawarich.Supervisor)
  end

  defp rails_server do
    case Application.get_env(:dawarich, :rails_argv) do
      [_ | _] = argv -> [{Dawarich.RailsServer, argv: argv}]
      _ -> []
    end
  end
end
