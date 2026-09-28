defmodule Dawarich.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    plan = Dawarich.Front.plan(Application.get_env(:dawarich, :rails_argv), System.get_env())
    Dawarich.Front.log(plan)
    Application.put_env(:dawarich, :rails_upstream, Dawarich.Front.upstream(plan))
    Application.put_env(:dawarich, :public_files, DawarichWeb.PublicFiles.boot_config())

    children =
      [
        Dawarich.Repo,
        {Oban, Application.fetch_env!(:dawarich, Oban)},
        {Phoenix.PubSub, name: Dawarich.PubSub}
      ] ++ Dawarich.Front.children(plan)

    Supervisor.start_link(children, strategy: :one_for_one, name: Dawarich.Supervisor)
  end
end
