defmodule Dawarich.Posters.NativeRendererTest do
  use ExUnit.Case, async: false
  alias Dawarich.Posters.{Geometry, NativeRenderer}
  @fake Path.expand("../../../../spec/fixtures/scripts/fake_poster_renderer.rb", __DIR__)

  setup do
    state =
      File.read!("test/fixtures/posters/overlapping_tracks_theme_basename.json")
      |> Jason.decode!()

    row = state["before"]

    %{
      state: state,
      poster: %{id: row["id"], name: row["name"], settings: row["settings"]},
      track: state["track"]
    }
  end

  @tag mutation: "ratio"
  test "renderer payload preserves dimensions theme basename title and PDF print values", ctx do
    result = NativeRenderer.render(ctx.poster, ctx.track, "de", command: ["ruby", @fake])
    job = Jason.decode!(result.png)
    expected = ctx.state["render_job"]
    assert Map.drop(job, ["output"]) == Map.drop(expected, ["output"])
    assert Map.drop(job["output"], ~w(png pdf)) == Map.drop(expected["output"], ~w(png pdf))
    assert job["size"] == %{"width" => 1200, "height" => 1600, "ratio" => 2}
    assert result.pdf == "PDF:" <> ctx.poster.name
    blank = %{ctx.poster | settings: Map.put(ctx.poster.settings, "title", "")}
    assert NativeRenderer.render(blank, ctx.track, "en", command: ["ruby", @fake]).pdf == "PDF:"
    assert Geometry.subtitle(ctx.poster.settings, "de") == expected["text"]["subtitle"]
  end

  @tag mutation: "pdf"
  test "renderer returns PNG PDF only on successful complete output", ctx do
    assert %{png: png, pdf: pdf} =
             NativeRenderer.render(ctx.poster, ctx.track, "en", command: ["ruby", @fake])

    assert byte_size(png) > 0
    assert byte_size(pdf) > 0

    assert_raise NativeRenderer.Error, ~r/output/, fn ->
      NativeRenderer.render(ctx.poster, ctx.track, "en", command: ["ruby", @fake, "no-pdf"])
    end

    assert_raise NativeRenderer.Error, ~r/failed/, fn ->
      NativeRenderer.render(ctx.poster, ctx.track, "en", command: ["ruby", @fake, "error"])
    end
  end

  @tag mutation: "kill"
  test "renderer error and timeout terminate child process group and clean temporary paths",
       ctx do
    root = Path.join(System.tmp_dir!(), "a9-render-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    for mode <- ~w(linger error-child) do
      {task, ready} =
        ready_renderer(ctx, mode, temp_root: root, timeout_ms: 1500, terminate_ms: 100)

      assert ready["pid"] == ready["pgrp"]
      send(task.pid, :render)
      assert_receive {:signal, "-TERM", pid}, 2000
      assert pid == ready["pid"]
      assert_receive {:signal, "-KILL", ^pid}, 1000
      assert inspect(catch_exit(Task.await(task))) =~ "Dawarich.Posters.NativeRenderer.Error"

      assert {_, status} =
               System.cmd("/bin/kill", ["-0", "#{ready["child"]}"], stderr_to_stdout: true)

      assert status != 0
      assert Path.wildcard(root <> "/.phoenix-tmp/*") == []
    end
  end

  @tag mutation: "group-argv"
  test "group kill argv separates options from negative PGID on macOS", ctx do
    parent = self()

    {task, ready} =
      ready_renderer(ctx, "linger",
        timeout_ms: 0,
        terminate_ms: 100,
        kill_command: fn executable, args, options ->
          send(parent, {:kill_argv, executable, args})
          System.cmd(executable, args, options)
        end
      )

    send(task.pid, :render)
    assert inspect(catch_exit(Task.await(task))) =~ "timed out"
    pgid = "-#{ready["pgrp"]}"
    assert_receive {:kill_argv, "/bin/kill", ["-0", "--", ^pgid]}
    assert_receive {:kill_argv, "/bin/kill", ["-TERM", "--", ^pgid]}
    assert_receive {:kill_argv, "/bin/kill", ["-KILL", "--", ^pgid]}
  end

  @tag mutation: "procps-group"
  test "procps group cleanup removes leader and descendant within termination budget", ctx do
    parent = self()

    {task, ready} =
      ready_renderer(ctx, "linger",
        timeout_ms: 0,
        kill_command: fn executable, args, options ->
          send(parent, :procps_kill)

          if Enum.at(args, 1) == "--",
            do: System.cmd(executable, args, options),
            else: {"failed to parse argument", 1}
        end
      )

    assert ready["pid"] == ready["pgrp"]

    assert {_, 0} =
             System.cmd("/bin/kill", ["-0", "--", "#{ready["child"]}"], stderr_to_stdout: true)

    started = System.monotonic_time(:millisecond)
    send(task.pid, :render)
    assert inspect(catch_exit(Task.await(task, 6_000))) =~ "timed out"
    assert System.monotonic_time(:millisecond) - started < 6_000
    assert_receive :procps_kill

    for member <- [ready["pid"], ready["child"]] do
      {_, status} = System.cmd("/bin/kill", ["-0", "--", "#{member}"], stderr_to_stdout: true)
      assert status != 0
    end

    {_, status} =
      System.cmd("/bin/kill", ["-0", "--", "-#{ready["pgrp"]}"], stderr_to_stdout: true)

    assert status != 0
  end

  @tag mutation: "term-status"
  test "failed TERM immediately falls through to group KILL", ctx do
    parent = self()

    {task, _ready} =
      ready_renderer(ctx, "linger",
        timeout_ms: 0,
        terminate_ms: 100,
        kill_command: fn executable, args, options ->
          if hd(args) == "-TERM" do
            send(self(), {Process.get(:renderer_port), {:data, "after-failed-term"}})
            {"TERM failed", 1}
          else
            System.cmd(executable, args, options)
          end
        end,
        on_output: fn output -> send(parent, {:unexpected_wait, output}) end
      )

    send(task.pid, :render)
    assert inspect(catch_exit(Task.await(task))) =~ "timed out"
    assert_receive {:signal, "-KILL", _}
    refute_receive {:unexpected_wait, _}
  end

  @tag mutation: "signal-esrch"
  test "group exit between liveness check and TERM or KILL preserves the renderer timeout", ctx do
    parent = self()

    for signal <- ~w(-KILL -TERM) do
      {task, ready} =
        ready_renderer(ctx, "exit-before-signal",
          timeout_ms: 0,
          terminate_ms: 0,
          kill_command: fn executable, args, options ->
            if hd(args) == signal do
              pid = args |> List.last() |> String.trim_leading("-")
              assert {_, 0} = System.cmd(executable, ["-USR1", "--", pid], options)
              port = Process.get(:renderer_port)
              assert_receive {^port, {:exit_status, 0}}, 1000
            end

            result = System.cmd(executable, args, options)
            if hd(args) == signal, do: send(parent, {:raced_signal, signal, result})
            result
          end
        )

      send(task.pid, :render)
      assert inspect(catch_exit(Task.await(task))) =~ "Poster renderer timed out after 0 ms"
      assert_receive {:raced_signal, ^signal, {_, status}}
      assert status != 0
      assert_receive {:signal, "-TERM", _}

      if signal == "-KILL",
        do: assert_receive({:signal, "-KILL", _}),
        else: refute_receive({:signal, "-KILL", _})

      assert {_, status} =
               System.cmd("/bin/kill", ["-0", "--", "-#{ready["pgrp"]}"], stderr_to_stdout: true)

      assert status != 0
    end
  end

  @tag mutation: "kill-status"
  test "failed group KILL is visible and still closes the port", ctx do
    parent = self()

    {task, _ready} =
      ready_renderer(ctx, "linger",
        timeout_ms: 0,
        terminate_ms: 0,
        kill_command: fn executable, args, options ->
          if hd(args) == "-KILL" do
            send(parent, {:cleanup_port, Process.get(:renderer_port)})
            {"Operation not permitted", 1}
          else
            System.cmd(executable, args, options)
          end
        end
      )

    send(task.pid, :render)

    assert inspect(catch_exit(Task.await(task))) =~
             "group KILL failed (1): Operation not permitted"

    assert_receive {:cleanup_port, port}
    assert Port.info(port) == nil
  end

  @tag mutation: "argv"
  test "renderer honors existing command override as argv without shell interpolation", ctx do
    saved = System.get_env("POSTER_RENDERER_CMD")

    on_exit(fn ->
      if saved,
        do: System.put_env("POSTER_RENDERER_CMD", saved),
        else: System.delete_env("POSTER_RENDERER_CMD")
    end)

    System.put_env("POSTER_RENDERER_CMD", "ruby #{@fake} argv literal;false")
    result = NativeRenderer.render(ctx.poster, ctx.track, "en")
    assert Jason.decode!(result.png)["argv"] == ["argv", "literal;false"]
  end

  @tag mutation: "absolute-deadline"
  test "continuous renderer output cannot bypass render or group KILL deadlines", ctx do
    parent = self()

    for mode <- ~w(continuous continuous-term) do
      {task, ready} =
        ready_renderer(ctx, mode,
          timeout_ms: 200,
          terminate_ms: 50,
          on_output: fn _ ->
            phase = Process.get(:renderer_phase, :render)

            unless Process.get({:output_seen, phase}) do
              send(parent, {:output_seen, phase})
              Process.put({:output_seen, phase}, true)
            end

            send(self(), {Process.get(:renderer_port), {:data, "queued-output"}})
          end
        )

      pid = ready["pid"]
      assert ready["pgrp"] == pid
      send(task.pid, :render)

      assert_receive {:output_seen, :render}, 1000
      assert_receive {:signal, "-TERM", ^pid}, 1000
      assert_receive {:output_seen, :cleanup}, 1000
      assert_receive {:signal, "-KILL", ^pid}, 1000
      assert inspect(catch_exit(Task.await(task))) =~ "Poster renderer timed out after 200 ms"

      for member <- [pid, ready["child"]] do
        assert {_, status} = System.cmd("/bin/kill", ["-0", "#{member}"], stderr_to_stdout: true)
        assert status != 0
      end
    end
  end

  @tag mutation: "configured-timeout"
  test "renderer reports the configured timeout before any output", ctx do
    assert_raise NativeRenderer.Error, "Poster renderer timed out after 0 ms", fn ->
      NativeRenderer.render(ctx.poster, ctx.track, "en",
        command: ["sh", "-c", "exec cat >/dev/null"],
        timeout_ms: 0,
        terminate_ms: 0
      )
    end
  end

  @tag mutation: "output-cap"
  test "renderer failure retains only bounded trailing diagnostics", ctx do
    error =
      assert_raise NativeRenderer.Error, fn ->
        NativeRenderer.render(ctx.poster, ctx.track, "en",
          command: ["ruby", @fake, "verbose-error"]
        )
      end

    assert byte_size(error.message) <= 16_384 + 64
    assert String.ends_with?(error.message, "diagnostic-tail")
  end

  defp ready_renderer(ctx, mode, opts) do
    parent = self()

    task =
      Task.async(fn ->
        NativeRenderer.render(
          ctx.poster,
          ctx.track,
          "en",
          Keyword.merge(
            [
              command: ["ruby", @fake, mode],
              on_spawn: fn port ->
                Process.put(:renderer_port, port)
                ready = renderer_ready(port, "")
                send(parent, {:ready, self(), ready})
                receive do: (:render -> :ok)
              end,
              on_signal: fn signal, pid ->
                Process.put(:renderer_phase, :cleanup)
                send(parent, {:signal, signal, pid})
              end
            ],
            opts
          )
        )
      end)

    Process.unlink(task.pid)
    on_exit(fn -> Process.exit(task.pid, :kill) end)
    task_pid = task.pid
    task_ref = task.ref

    ready =
      receive do
        {:ready, ^task_pid, ready} -> ready
        {:DOWN, ^task_ref, :process, ^task_pid, reason} -> flunk(inspect(reason))
      end

    on_exit(fn ->
      System.cmd("/bin/kill", ["-KILL", "--", "-#{ready["pgrp"]}"], stderr_to_stdout: true)
    end)

    {task, ready}
  end

  defp renderer_ready(port, output) do
    receive do
      {^port, {:data, data}} ->
        case String.split(output <> data, "\n", parts: 2) do
          [line, rest] ->
            if rest != "", do: send(self(), {port, {:data, rest}})
            Jason.decode!(line)

          [partial] ->
            renderer_ready(port, partial)
        end

      {^port, {:exit_status, status}} ->
        flunk("renderer exited before readiness: #{status}")
    end
  end
end
