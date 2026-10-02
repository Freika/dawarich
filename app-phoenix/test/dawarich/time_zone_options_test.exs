defmodule Dawarich.TimeZoneOptionsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Dawarich.TimeZoneOptions

  @corpus "test/fixtures/settings_corpus.json" |> File.read!() |> Jason.decode!()

  @tag :tmp_dir
  test "reads Rails' export as {label, iana} pairs in Rails' order", %{tmp_dir: dir} do
    path = Path.join(dir, "time_zones.json")
    File.write!(path, Jason.encode!(%{"options" => @corpus["time_zone_options"]}))

    assert TimeZoneOptions.read(path) ==
             Enum.map(@corpus["time_zone_options"], fn [label, iana] -> {label, iana} end)

    assert {"(GMT+09:00) Asia/Tokyo", "Asia/Tokyo"} in TimeZoneOptions.read(path)
  end

  @tag :tmp_dir
  test "a missing export gives an empty list and one warning", %{tmp_dir: dir} do
    previous = Application.get_env(:dawarich, :rails_root)
    Application.put_env(:dawarich, :rails_root, dir)
    :persistent_term.erase(TimeZoneOptions)

    on_exit(fn ->
      :persistent_term.erase(TimeZoneOptions)
      Application.put_env(:dawarich, :rails_root, previous)
    end)

    log = capture_log(fn -> assert TimeZoneOptions.list() == [] end)
    assert log =~ "phoenix:time_zones"
    assert capture_log(fn -> assert TimeZoneOptions.list() == [] end) == ""
  end
end
