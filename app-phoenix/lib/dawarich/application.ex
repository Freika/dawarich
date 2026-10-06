defmodule Dawarich.Application do
  @moduledoc false
  use Application

  alias Dawarich.Front

  @impl true
  def start(_type, _args) do
    Dawarich.ErrorReporting.start()
    plan = plan(Application.get_env(:dawarich, :rails_argv), System.get_env())
    start_plan(plan)
  end

  def plan(argv, env) do
    case env["DAWARICH_PROCESS_ROLE"] do
      "sidekiq_idle" -> :sidekiq_idle
      role when role in [nil, "", "web"] -> web_plan(argv, env)
      _ -> raise ArgumentError, "DAWARICH_PROCESS_ROLE must be web or sidekiq_idle"
    end
  end

  defp web_plan(
         _argv,
         %{
           "SELF_HOSTED" => "false",
           "DAWARICH_PHOENIX_LIFECYCLE" => "true"
         } = env
       ) do
    argv =
      case env["DAWARICH_NATIVE_ARGS"] do
        args when is_binary(args) ->
          args |> String.replace_suffix("\x1F", "") |> String.split("\x1F")

        _ ->
          nil
      end

    case Front.native_plan(argv, env) do
      {:native, _} = plan -> plan
      _ -> raise ArgumentError, "Native Cloud web requires a supported listener command"
    end
  end

  defp web_plan(argv, env), do: Front.plan(argv, env)

  defp start_plan(:sidekiq_idle) do
    Supervisor.start_link(children(:sidekiq_idle),
      strategy: :one_for_one,
      name: Dawarich.Supervisor
    )
  end

  defp start_plan(plan) do
    Dawarich.QrCache.create_table()
    Dawarich.TtlCache.create_table()

    if jobs_runtime?() do
      Oban.Telemetry.attach_default_logger(level: :info, events: [:job, :peer])
    end

    Front.log(plan)
    Application.put_env(:dawarich, :rails_upstream, Front.upstream(plan))
    Application.put_env(:dawarich, :public_files, DawarichWeb.PublicFiles.boot_config())
    Application.put_env(:dawarich, :allowed_hosts, DawarichWeb.HostAuthorization.boot_config())

    Supervisor.start_link(children(plan), strategy: :one_for_one, name: Dawarich.Supervisor)
  end

  def children(:sidekiq_idle), do: []

  def children(plan) do
    oban = Application.fetch_env!(:dawarich, Oban)
    node = oban[:node] || Oban.Config.node_name()
    cron = [crontab: Dawarich.Jobs.Registry.crontab(), timezone: "Etc/UTC"]

    Dawarich.Metrics.children(plan) ++
      [Dawarich.Repo] ++
      redis() ++
      [
        {Oban, Keyword.put(oban, :cron, cron)},
        {Phoenix.PubSub, name: Dawarich.PubSub}
      ] ++
      Dawarich.Cable.Bus.child_specs() ++
      Front.children(plan, [{"DAWARICH_PHOENIX_NODE", node}]) ++ jobs(node)
  end

  defp redis,
    do:
      if(jobs_runtime?(),
        do: Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        else: []
      )

  defp jobs(node) do
    if jobs_runtime?(),
      do: [
        {Dawarich.Jobs.Supervisor,
         node: node, entries: Application.get_env(:dawarich, :job_entries, [])},
        Dawarich.Cable.EventsRelay.supervisor_spec()
      ],
      else: []
  end

  defp jobs_runtime?, do: Application.get_env(:dawarich, :jobs_runtime, true)
end
