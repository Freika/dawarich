defmodule Dawarich.Application do
  @moduledoc false
  use Application

  alias Dawarich.Front

  @impl true
  def start(_type, _args) do
    if jobs_runtime?() do
      Oban.Telemetry.attach_default_logger(level: :info, events: [:job, :peer])
    end

    plan = Front.plan(Application.get_env(:dawarich, :rails_argv), System.get_env())
    Front.log(plan)
    Application.put_env(:dawarich, :rails_upstream, Front.upstream(plan))
    Application.put_env(:dawarich, :public_files, DawarichWeb.PublicFiles.boot_config())

    Supervisor.start_link(children(plan), strategy: :one_for_one, name: Dawarich.Supervisor)
  end

  def children(plan) do
    oban = Application.fetch_env!(:dawarich, Oban)
    node = oban[:node] || Oban.Config.node_name()
    cron = [crontab: Dawarich.Jobs.Registry.crontab(), timezone: "Etc/UTC"]

    [Dawarich.Repo] ++
      redis() ++
      [
        {Oban, Keyword.put(oban, :cron, cron)},
        {Phoenix.PubSub, name: Dawarich.PubSub}
      ] ++ Front.children(plan, [{"DAWARICH_PHOENIX_NODE", node}]) ++ jobs(node)
  end

  defp redis, do: if(jobs_runtime?(), do: Dawarich.Redis.child_specs(), else: [])

  defp jobs(node) do
    if jobs_runtime?(), do: [{Dawarich.Jobs.Supervisor, node: node}], else: []
  end

  defp jobs_runtime?, do: Application.get_env(:dawarich, :jobs_runtime, true)
end
