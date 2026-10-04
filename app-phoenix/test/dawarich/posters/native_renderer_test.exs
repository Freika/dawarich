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
    parent = self()
    root = Path.join(System.tmp_dir!(), "a9-render-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    for mode <- ~w(linger error-child) do
      task =
        Task.async(fn ->
          NativeRenderer.render(ctx.poster, ctx.track, "en",
            command: ["ruby", @fake, mode],
            temp_root: root,
            timeout_ms: 1500,
            terminate_ms: 100,
            on_output: &send(parent, {:ready, &1}),
            on_signal: fn signal, pid -> send(parent, {:signal, signal, pid}) end
          )
        end)

      assert_receive {:ready, output}, 1500
      ready = Jason.decode!(String.trim(output))
      assert ready["pid"] == ready["pgrp"]

      on_exit(fn ->
        System.cmd("/bin/kill", ["-KILL", "-#{ready["pgrp"]}"], stderr_to_stdout: true)
      end)

      Process.unlink(task.pid)
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
      task =
        Task.async(fn ->
          NativeRenderer.render(ctx.poster, ctx.track, "en",
            command: ["ruby", @fake, mode],
            timeout_ms: 200,
            terminate_ms: 50,
            on_output: fn data ->
              unless Process.get(:renderer_ready) do
                ready = data |> String.split("\n", parts: 2) |> hd() |> Jason.decode!()
                send(parent, {:ready, ready})
                Process.put(:renderer_ready, true)
              end

              {:links, links} = Process.info(self(), :links)
              port = Enum.find(links, &is_port/1)
              send(self(), {port, {:data, "queued-output"}})
            end,
            on_signal: fn signal, pid -> send(parent, {:signal, signal, pid}) end
          )
        end)

      Process.unlink(task.pid)
      on_exit(fn -> Process.exit(task.pid, :kill) end)
      assert_receive {:ready, ready}, 1000
      pid = ready["pid"]
      assert ready["pgrp"] == pid

      on_exit(fn ->
        System.cmd("/bin/kill", ["-KILL", "-#{pid}"], stderr_to_stdout: true)
      end)

      assert_receive {:signal, "-TERM", ^pid}, 1000
      assert_receive {:signal, "-KILL", ^pid}, 1000
      assert inspect(catch_exit(Task.await(task))) =~ "Poster renderer timed out"

      for member <- [pid, ready["child"]] do
        assert {_, status} = System.cmd("/bin/kill", ["-0", "#{member}"], stderr_to_stdout: true)
        assert status != 0
      end
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
end
