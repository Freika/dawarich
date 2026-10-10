defmodule Dawarich.FrontTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Dawarich.{Front, RailsServer}
  alias DawarichWeb.RailsProxy.Upstream

  @prod %{"RAILS_ENV" => "production"}
  @opts [upstream_port: 41_000, ipv6?: false]

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp rails_command(port), do: ~w(bundle exec bin/rails server -b 127.0.0.1) ++ ["-p", "#{port}"]

  @tag :a12f4_a03_2
  test "native bind failure is terminal without a fallback listener" do
    port = free_port()
    argv = ~w(bin/rails server -b 127.0.0.1) ++ ["-p", "#{port}"]
    assert {:native, {{127, 0, 0, 1}, ^port}} = plan = Front.native_plan(argv, @prod)
    assert Front.upstream(plan) == nil
    assert Front.native_plan(~w(sidekiq), @prod) == :sidekiq_idle
    assert Front.native_plan(~w(rails db:migrate), @prod) == :migrate
    assert {:error, _} = Front.native_plan([], @prod)

    assert [endpoint, {Dawarich.Front.Drainer, []}] = Front.children(plan)

    assert %{
             id: DawarichWeb.Endpoint,
             shutdown: 5_000,
             start: {DawarichWeb.Endpoint, :start_link, [opts]}
           } = endpoint

    assert opts[:server] == true
    assert opts[:http] == Front.http_options({127, 0, 0, 1}, port)

    assert opts[:secret_key_base] ==
             Dawarich.RailsSecret.endpoint_secret(Dawarich.RailsSecret.fetch())

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

    {:ok, busy} = :gen_tcp.listen(port, ip: {127, 0, 0, 1}, active: false)
    assert Front.native_plan(argv, @prod) == plan
    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        result = Supervisor.start_link(Front.children(plan), strategy: :one_for_one)
        send(owner, {:bind_result, result})
        if match?({:ok, _}, result), do: Supervisor.stop(elem(result, 1))
      end)

    assert_receive {:bind_result, {:error, reason}}, 1_000
    assert inspect(reason) =~ "eaddrinuse"
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    :ok = :gen_tcp.close(busy)

    sup =
      start_supervised!(%{
        id: :native_front,
        start: {Supervisor, :start_link, [Front.children(plan), [strategy: :one_for_one]]},
        type: :supervisor
      })

    assert Enum.map(Supervisor.which_children(sup), &elem(&1, 0)) ==
             [Dawarich.Front.Drainer, DawarichWeb.Endpoint]

    {:ok, bandit} = Bandit.PhoenixAdapter.bandit_pid(DawarichWeb.Endpoint)
    assert {:ok, {{127, 0, 0, 1}, ^port}} = ThousandIsland.listener_info(bandit)

    assert {:ok, {{_, 200, _}, _, body}} =
             :httpc.request(
               :get,
               {~c"http://127.0.0.1:#{port}/phoenix/js/phoenix.mjs", []},
               [timeout: 2_000, connect_timeout: 1_000],
               body_format: :binary
             )

    assert body == File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.mjs"))
    assert Supervisor.stop(sup) == :ok
  end

  test "without a server command there is no proxy and no Puma" do
    assert Front.plan(nil, @prod, @opts) == :none
    assert Front.children(:none) == [DawarichWeb.Endpoint]
    assert Front.upstream(:none) == nil
  end

  test "a server command becomes Puma on loopback behind a Phoenix listener" do
    port = free_port()

    assert {:proxy, %{public: {{127, 0, 0, 1}, ^port}, upstream: 41_000, puma_argv: puma}} =
             plan = Front.plan(rails_command(port), @prod, @opts)

    assert puma == ~w(bundle exec bin/rails server -b 127.0.0.1 -p 41000)
    assert Front.upstream(plan) == {{127, 0, 0, 1}, 41_000}
  end

  test "the stored upstream is an address tuple that opens a TCP connection" do
    {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    plan =
      Front.plan(rails_command(free_port()), @prod,
        upstream_port: port,
        ipv6?: false
      )

    assert {:proxy, _} = plan
    assert {{127, 0, 0, 1}, ^port} = Front.upstream(plan)
    assert {:ok, socket} = Upstream.open(Front.upstream(plan))
    assert {:ok, accepted} = :gen_tcp.accept(listener)
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(accepted)
  end

  test "DAWARICH_PROXY=off runs Puma exactly as the command says" do
    argv = rails_command(free_port())

    for value <- ~w(off false 0 no OFF) do
      assert {:direct, ^argv, cause} =
               Front.plan(argv, Map.put(@prod, "DAWARICH_PROXY", value), @opts)

      assert cause == "DAWARICH_PROXY=#{value}"
    end
  end

  test "DAWARICH_PROXY=off decides before Phoenix binds anything" do
    argv = rails_command(free_port())
    env = Map.put(@prod, "DAWARICH_PROXY", "off")
    test = self()
    :erlang.trace_pattern({:gen_tcp, :listen, 2}, true, [:local])
    on_exit(fn -> :erlang.trace_pattern({:gen_tcp, :listen, 2}, false, [:local]) end)

    planner =
      spawn(fn ->
        receive do
          :go -> send(test, {:plan, Front.plan(argv, env, ipv6?: false)})
        end
      end)

    :erlang.trace(planner, true, [:call])
    send(planner, :go)

    assert_receive {:plan, {:direct, ^argv, "DAWARICH_PROXY=off"}}
    ref = :erlang.trace_delivered(planner)
    assert_receive {:trace_delivered, ^planner, ^ref}
    refute_received {:trace, ^planner, :call, {:gen_tcp, :listen, _}}
  end

  test "an occupied public port runs Puma directly and names the address" do
    {:ok, busy} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(busy)
    argv = rails_command(port)

    assert {:direct, ^argv, cause} = Front.plan(argv, @prod, @opts)
    assert cause =~ "127.0.0.1:#{port} is not available"
  end

  test "a command Phoenix cannot front runs as given" do
    argv = ["sh", "-c", "exit 0"]

    assert {:direct, ^argv, "the server command is not one Phoenix can front"} =
             Front.plan(argv, @prod, @opts)
  end

  test "Puma starts before the listener, so the listener drains first on shutdown" do
    plan =
      {:proxy, %{public: {{0, 0, 0, 0}, 3000}, upstream: 41_000, puma_argv: ~w(bundle exec puma)}}

    assert [{RailsServer, puma}, endpoint, {Dawarich.Front.Drainer, []}] = Front.children(plan)
    assert puma[:argv] == ~w(bundle exec puma)
    assert puma[:env] == [{"DAWARICH_BEHIND_PHOENIX", "1"}]

    assert %{
             id: DawarichWeb.Endpoint,
             shutdown: 5_000,
             start: {DawarichWeb.Endpoint, :start_link, [opts]}
           } = endpoint

    assert opts[:server] == true
    assert opts[:http][:ip] == {0, 0, 0, 0}
    assert opts[:http][:port] == 3000
    assert get_in(opts, [:http, :thousand_island_options, :shutdown_timeout]) == 5_000
    assert byte_size(opts[:secret_key_base]) >= 64
  end

  test "Bandit never compresses, never speaks HTTP/2 and accepts what Puma accepts" do
    http = Front.http_options({0, 0, 0, 0, 0, 0, 0, 0}, 3000)

    assert http[:http_options][:compress] == false
    assert http[:http_2_options][:enabled] == false
    assert http[:http_1_options][:max_request_line_length] >= 12_288
    assert http[:http_1_options][:max_header_length] >= 256 + 81_920
    assert :inet6 in http[:thousand_island_options][:transport_options]
  end

  test "a directly started Puma never inherits the proxy marker" do
    assert [{RailsServer, opts}] = Front.children({:direct, ~w(bundle exec puma), "cause"})
    assert opts[:env] == [{"DAWARICH_BEHIND_PHOENIX", false}]
  end

  test "a Puma environment entry named like the proxy marker cannot flip it" do
    argv = ["sh", "-c", ~S(echo "[${DAWARICH_BEHIND_PHOENIX:-unset}]")]
    proxy = {:proxy, %{public: {{127, 0, 0, 1}, 3000}, upstream: 41_000, puma_argv: argv}}
    test = self()

    for {plan, puma_env, expected} <- [
          {{:direct, argv, "cause"}, [{"DAWARICH_BEHIND_PHOENIX", "1"}], "[unset]\n"},
          {proxy, [{"DAWARICH_BEHIND_PHOENIX", false}], "[1]\n"}
        ] do
      {RailsServer, opts} = List.keyfind(Front.children(plan, puma_env), RailsServer, 0)
      capture = [sink: &send(test, {:out, &1}), on_exit: &send(test, {:exited, &1})]

      start_supervised!({RailsServer, opts ++ capture}, id: expected)

      assert_receive {:exited, 0}, 5_000
      assert collected_output() == expected
    end
  end

  defp collected_output(acc \\ "") do
    receive do
      {:out, data} -> collected_output(acc <> data)
    after
      0 -> acc
    end
  end

  test "falling back is logged in one line that names the cause" do
    log = capture_log([level: :warning], fn -> Front.log({:direct, [], "DAWARICH_PROXY=off"}) end)

    assert log =~
             "Phoenix proxy off (DAWARICH_PROXY=off); Puma serves the server command's own address"
  end

  test "Puma's loopback port lies below the ephemeral range" do
    assert Front.free_loopback_port() in 20_000..32_767
  end
end
