defmodule Dawarich.ApplicationTest do
  use ExUnit.Case, async: false

  alias Dawarich.RailsServer

  @argv ~w(bundle exec puma)
  @proxy {:proxy, %{public: {{127, 0, 0, 1}, 3000}, upstream: 41_000, puma_argv: @argv}}
  @direct {:direct, @argv, "DAWARICH_PROXY=off"}

  setup do
    jobs = Application.get_env(:dawarich, :jobs_runtime)
    oban = Application.fetch_env!(:dawarich, Oban)
    Application.put_env(:dawarich, :jobs_runtime, true)

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_runtime, jobs)
      Application.put_env(:dawarich, Oban, oban)
    end)

    %{oban: oban}
  end

  defp ids(plan),
    do: Enum.map(Dawarich.Application.children(plan), &Supervisor.child_spec(&1, []).id)

  test "stops the jobs first, then the front, then PubSub, Oban and the repo, in every front mode" do
    base = [Dawarich.Repo, Oban, Phoenix.PubSub.Supervisor]

    assert ids(:none) == base ++ [DawarichWeb.Endpoint, Dawarich.Jobs.Supervisor]
    assert ids(@direct) == base ++ [RailsServer, Dawarich.Jobs.Supervisor]

    assert ids(@proxy) ==
             base ++
               [
                 RailsServer,
                 DawarichWeb.Endpoint,
                 Dawarich.Front.Drainer,
                 Dawarich.Jobs.Supervisor
               ]
  end

  test "leaves the jobs out when the jobs runtime is off" do
    Application.put_env(:dawarich, :jobs_runtime, false)

    assert ids(@proxy) == [
             Dawarich.Repo,
             Oban,
             Phoenix.PubSub.Supervisor,
             RailsServer,
             DawarichWeb.Endpoint,
             Dawarich.Front.Drainer
           ]
  end

  test "gives Puma and the jobs the configured Oban node before the proxy marker, and Oban the crontab in UTC",
       %{oban: config} do
    node = "web-3f2a9c1d7b44"
    Application.put_env(:dawarich, Oban, Keyword.put(config, :node, node))

    for {plan, marker} <- [{@proxy, "1"}, {@direct, false}] do
      children = Dawarich.Application.children(plan)
      {Oban, oban} = Enum.at(children, 1)
      {RailsServer, puma} = List.keyfind(children, RailsServer, 0)
      {Dawarich.Jobs.Supervisor, jobs} = List.last(children)

      assert oban[:node] == node
      assert oban[:cron] == [crontab: Dawarich.Jobs.Registry.crontab(), timezone: "Etc/UTC"]
      assert jobs[:node] == node
      assert puma[:env] == [{"DAWARICH_PHOENIX_NODE", node}, {"DAWARICH_BEHIND_PHOENIX", marker}]
    end
  end
end
