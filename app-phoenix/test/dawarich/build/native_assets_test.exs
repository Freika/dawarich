defmodule Dawarich.Build.NativeAssetsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @moduletag :tmp_dir

  defp build!(dir) do
    assert 0 ==
             Esbuild.install_and_run(:native, [
               "--outdir=#{dir}",
               "--metafile=#{Path.join(dir, "meta.json")}",
               "--log-level=warning"
             ])

    dir
  end

  defp inputs(dir) do
    dir
    |> Path.join("meta.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("inputs")
    |> Map.keys()
  end

  test "the native bundle includes LiveView and no Hotwire module", %{tmp_dir: dir} do
    inputs = dir |> build!() |> inputs()

    assert Enum.any?(inputs, &String.contains?(&1, "phoenix_live_view"))
    refute Enum.any?(inputs, &Regex.match?(~r/@hotwired|stimulus|turbo|rails_bridge/i, &1))
  end

  test "emoji-mart is a separate lazily loaded chunk", %{tmp_dir: dir} do
    build!(dir)
    app = File.read!(Path.join(dir, "app.js"))
    chunks = dir |> Path.join("*.js") |> Path.wildcard()

    refute app =~ "EmojiMart"
    assert length(chunks) > 1
  end

  test "the endpoint serves files from the native output directory" do
    native = Application.app_dir(:dawarich, "priv/static/native")
    probe = "probe-#{System.unique_integer([:positive])}.js"
    File.mkdir_p!(native)
    File.write!(Path.join(native, probe), "export {}")
    on_exit(fn -> File.rm(Path.join(native, probe)) end)

    conn = DawarichWeb.Endpoint.call(conn(:get, "/native/" <> probe), [])

    assert conn.status == 200
    assert hd(Plug.Conn.get_resp_header(conn, "content-type")) =~ "javascript"
  end

  test "native_path points at the native output through the endpoint's static paths" do
    assert DawarichWeb.Assets.native_path("app.js") == "/native/app.js"
  end
end
