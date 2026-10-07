defmodule Dawarich.ApplicationTest do
  use ExUnit.Case, async: false

  alias Dawarich.RailsServer

  @argv ~w(bundle exec puma)
  @proxy {:proxy, %{public: {{127, 0, 0, 1}, 3000}, upstream: 41_000, puma_argv: @argv}}
  @direct {:direct, @argv, "DAWARICH_PROXY=off"}

  setup do
    entries = Application.get_env(:dawarich, :job_entries, [])

    Application.put_env(
      :dawarich,
      :job_entries,
      Dawarich.Jobs.Claimer.entries("command:visits.suggest")
    )

    jobs = Application.get_env(:dawarich, :jobs_runtime)
    oban = Application.fetch_env!(:dawarich, Oban)
    Application.put_env(:dawarich, :jobs_runtime, true)

    on_exit(fn ->
      Application.put_env(:dawarich, :job_entries, entries)
      Application.put_env(:dawarich, :jobs_runtime, jobs)
      Application.put_env(:dawarich, Oban, oban)
    end)

    %{oban: oban}
  end

  defp ids(plan),
    do: Enum.map(Dawarich.Application.children(plan), &Supervisor.child_spec(&1, []).id)

  test "opt-in Cloud web selects the native listener without a Rails child or upstream" do
    env = %{
      "RAILS_ENV" => "production",
      "SELF_HOSTED" => "false",
      "DAWARICH_PHOENIX_LIFECYCLE" => "true",
      "DAWARICH_PROXY" => "off"
    }

    for {argv, address} <- [
          {~w(puma -C config/puma.rb -p 5000), {{0, 0, 0, 0}, 5000}},
          {["puma", "--config=config/puma.rb", "--bind", "tcp://[::1]:5000"],
           {{0, 0, 0, 0, 0, 0, 0, 1}, 5000}}
        ] do
      input = Map.put(env, "DAWARICH_NATIVE_ARGS", Enum.join(argv, "\x1F") <> "\x1F")
      assert {:native, ^address} = plan = Dawarich.Application.plan(@argv, input)
      assert Dawarich.Front.upstream(plan) == nil
      refute RailsServer in ids(plan)
      assert Dawarich.Front.Drainer in ids(plan)

      for disabled <- [
            Map.delete(input, "DAWARICH_PHOENIX_LIFECYCLE"),
            Map.put(input, "DAWARICH_PHOENIX_LIFECYCLE", "false"),
            Map.delete(input, "SELF_HOSTED"),
            Map.put(input, "SELF_HOSTED", "true")
          ] do
        assert Dawarich.Application.plan(@argv, disabled) == @direct
      end
    end

    for argv <- [
          ~w(puma -C custom.rb -p 5000),
          ["puma", "-C", "config/puma.rb", "--tag", "two words"],
          ~w(puma -p 5000 -p 5001),
          ~w(rails runner),
          ~w(sidekiq),
          []
        ] do
      input = Map.put(env, "DAWARICH_NATIVE_ARGS", Enum.join(argv, "\x1F") <> "\x1F")
      assert_raise ArgumentError, fn -> Dawarich.Application.plan(nil, input) end
    end

    assert_raise ArgumentError, fn -> Dawarich.Application.plan(nil, env) end
  end

  test "adding native front helpers preserves existing proxy and idle role selection" do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    argv = ~w(bundle exec bin/rails server -b 127.0.0.1) ++ ["-p", "#{port}"]
    env = %{"RAILS_ENV" => "production"}

    assert Dawarich.Front.native_plan(argv, env) == {:native, {{127, 0, 0, 1}, port}}

    for role <- [nil, "", "web"] do
      assert {:proxy, %{public: {{127, 0, 0, 1}, ^port}, upstream: upstream, puma_argv: puma}} =
               Dawarich.Application.plan(argv, Map.put(env, "DAWARICH_PROCESS_ROLE", role))

      assert upstream in 20_000..32_767
      assert puma == ~w(bundle exec bin/rails server -b 127.0.0.1) ++ ["-p", "#{upstream}"]
    end

    assert {:direct, ^argv, "DAWARICH_PROXY=off"} =
             Dawarich.Application.plan(argv, Map.put(env, "DAWARICH_PROXY", "off"))

    assert Dawarich.Application.plan(argv, Map.put(env, "DAWARICH_PROCESS_ROLE", "sidekiq_idle")) ==
             :sidekiq_idle

    assert Dawarich.Application.plan(nil, env) == :none
    assert {:error, _} = Dawarich.Front.native_plan(nil, env)
  end

  test "sidekiq idle role starts no Repo Endpoint Puma Oban relay or cron and exits cleanly on shutdown" do
    idle = Dawarich.Application.plan(@argv, %{"DAWARICH_PROCESS_ROLE" => "sidekiq_idle"})
    assert idle == :sidekiq_idle
    assert ids(idle) == []

    {:ok, supervisor} =
      Supervisor.start_link(Dawarich.Application.children(idle), strategy: :one_for_one)

    assert Supervisor.which_children(supervisor) == []
    monitor = Process.monitor(supervisor)
    assert Supervisor.stop(supervisor) == :ok
    assert_receive {:DOWN, ^monitor, :process, ^supervisor, :normal}
    assert Dawarich.Application.plan(nil, %{}) == :none
    assert Dawarich.Application.plan(nil, %{"DAWARICH_PROCESS_ROLE" => "web"}) == :none

    assert_raise ArgumentError, "DAWARICH_PROCESS_ROLE must be web or sidekiq_idle", fn ->
      Dawarich.Application.plan(nil, %{"DAWARICH_PROCESS_ROLE" => "sidekiq"})
    end
  end

  test "stops the jobs first, then the front, then PubSub, Oban and the repo, in every front mode" do
    base = [
      Dawarich.Repo,
      Redix,
      Dawarich.Redis.Cache,
      Dawarich.Geocoding.RateLimiter,
      Oban,
      Dawarich.Tracks.MapMatching.Tasks,
      Dawarich.Tracks.MapMatching.Deferred,
      Phoenix.PubSub.Supervisor
    ]

    jobs = [Dawarich.Jobs.Supervisor, Dawarich.Cable.EventsRelay.Supervisor]
    assert ids(:none) == base ++ [DawarichWeb.Endpoint | jobs]
    assert ids(@direct) == base ++ [RailsServer | jobs]

    assert ids(@proxy) ==
             base ++
               [
                 RailsServer,
                 DawarichWeb.Endpoint,
                 Dawarich.Front.Drainer | jobs
               ]
  end

  test "Redis starts before Oban when the jobs runtime is on" do
    Application.put_env(:dawarich, :jobs_runtime, true)

    assert Enum.take(ids(:none), 5) == [
             Dawarich.Repo,
             Redix,
             Dawarich.Redis.Cache,
             Dawarich.Geocoding.RateLimiter,
             Oban
           ]

    Application.put_env(:dawarich, :jobs_runtime, false)
    refute Redix in ids(:none)
    refute Dawarich.Redis.Cache in ids(:none)
  end

  test "both Redis connections start before Oban" do
    Application.put_env(:dawarich, :jobs_runtime, true)

    assert Enum.take(ids(:none), 5) == [
             Dawarich.Repo,
             Redix,
             Dawarich.Redis.Cache,
             Dawarich.Geocoding.RateLimiter,
             Oban
           ]
  end

  test "leaves the jobs out when the jobs runtime is off" do
    Application.put_env(:dawarich, :jobs_runtime, false)

    assert ids(@proxy) == [
             Dawarich.Repo,
             Dawarich.Geocoding.RateLimiter,
             Oban,
             Dawarich.Tracks.MapMatching.Tasks,
             Dawarich.Tracks.MapMatching.Deferred,
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
      {Oban, oban} = Enum.at(children, 4)
      {RailsServer, puma} = List.keyfind(children, RailsServer, 0)
      {Dawarich.Jobs.Supervisor, jobs} = List.keyfind(children, Dawarich.Jobs.Supervisor, 0)

      assert oban[:node] == node

      assert oban[:cron] ==
               {Dawarich.Jobs.TickScheduler,
                [crontab: Dawarich.Jobs.Registry.crontab(), timezone: "Etc/UTC"]}

      assert jobs[:node] == node
      assert jobs[:entries] == Dawarich.Jobs.Claimer.entries("command:visits.suggest")
      assert puma[:env] == [{"DAWARICH_PHOENIX_NODE", node}, {"DAWARICH_BEHIND_PHOENIX", marker}]
    end
  end

  @tag :a12f4_a03_1
  test "standalone application starts only the native requested listener" do
    for hosted <- [nil, "true", "false"], role <- [nil, "", "web"] do
      env = %{
        "DAWARICH_RAILS" => "off",
        "SELF_HOSTED" => hosted,
        "DAWARICH_PROCESS_ROLE" => role,
        "BINDING" => "127.0.0.1",
        "PORT" => "4321"
      }

      assert {:native, {{127, 0, 0, 1}, 4321}} = plan = Dawarich.Application.plan(nil, env)
      assert Enum.count(ids(plan), &(&1 == DawarichWeb.Endpoint)) == 1
      assert Enum.count(ids(plan), &(&1 == Dawarich.Front.Drainer)) == 1
      refute RailsServer in ids(plan)
      assert Dawarich.Front.upstream(plan) == nil
      assert [endpoint, {Dawarich.Front.Drainer, []}] = Dawarich.Front.children(plan)

      assert endpoint.start |> elem(2) |> hd() |> Keyword.fetch!(:http) ==
               Dawarich.Front.http_options({127, 0, 0, 1}, 4321)
    end
  end

  @tag :a12f4_a03_3
  test "ordinary test startup has no public listener while native release startup requires readiness" do
    config = Config.Reader.read!(Path.expand("../../config/test.exs", __DIR__), env: :test)
    assert config[:dawarich][:front_runtime] == false
    assert Dawarich.Application.runtime_plan(nil, %{"DAWARICH_RAILS" => "off"}) == :none

    assert Dawarich.Application.runtime_plan(nil, %{"DAWARICH_PROCESS_ROLE" => "sidekiq_idle"}) ==
             :sidekiq_idle

    script = ~S"""
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    System.put_env("PORT", Integer.to_string(port))
    {:ok, _} = Application.ensure_all_started(:dawarich)
    if Bandit.PhoenixAdapter.bandit_pid(DawarichWeb.Endpoint) != {:error, :no_server_found}, do: System.halt(21)
    IO.puts("test startup has no public listener")
    """

    {output, status} = native_subprocess(script)
    assert status == 0, "exit #{status}: #{output}"
    assert output =~ "test startup has no public listener"

    script = ~S"""
    Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Dawarich.Repo.start_link()
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Dawarich.Repo.query!("DELETE FROM public.schema_migrations WHERE version=(SELECT max(version) FROM public.schema_migrations)", [], log: false)
    Application.put_env(:dawarich, :front_runtime, true)
    source = File.read!("lib/dawarich/application.ex")
    Code.compile_string(String.replace(source, "defmodule Dawarich.Application do", "defmodule Dawarich.NativeBootProbe do"))
    IO.puts("pending public version prepared")
    Dawarich.NativeBootProbe.start(:normal, [])
    IO.puts("native children started")
    """

    {output, status} = native_subprocess(script)
    assert output =~ "pending public version prepared"
    assert status == 3, "exit #{status}: #{output}"
    refute output =~ "native children started"
  end

  defp native_subprocess(script) do
    System.cmd("mix", ["run", "--no-start", "-e", script],
      cd: Path.expand("../..", __DIR__),
      env: [
        {"DAWARICH_RAILS", "off"},
        {"DAWARICH_RAILS_ARGS", nil},
        {"DAWARICH_NATIVE_ARGS", nil},
        {"DAWARICH_PROCESS_ROLE", "web"},
        {"ERL_FLAGS", "+S 2:2"}
      ],
      stderr_to_stdout: true
    )
  end
end
