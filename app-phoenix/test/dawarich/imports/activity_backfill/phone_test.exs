defmodule Dawarich.Imports.ActivityBackfill.PhoneTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.ActivityBackfill.Phone
  alias Dawarich.Test.ActivityBackfillFixtures, as: F

  setup do
    path = Path.join(System.tmp_dir!(), "a12rel-phone-#{System.unique_integer([:positive])}.json")

    on_exit(fn ->
      F.cleanup()
      F.query("ALTER TABLE points ALTER COLUMN motion_data SET NOT NULL")
      File.rm(path)
    end)

    %{path: path}
  end

  test "phone nearest activity preserves sixty second and tie rules independently of file order",
       %{path: path} do
    for name <- ["phone_object", "phone_array"] do
      profile = F.profile(name)
      F.seed!(profile)
      before = F.snapshot()
      File.write!(path, F.input(profile))
      assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok
      F.assert_points(profile["after"])
      F.assert_untouched(before)
      assert F.committed_snapshot() == F.snapshot()
      assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok
      F.assert_points(profile["after"])
    end

    profile = F.profile("phone_array")
    F.seed!(profile)
    before = F.snapshot()
    File.write!(path, F.input(profile) <> " trailing")
    assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok
    assert F.snapshot() == before

    for offset <- [59, 60, 61] do
      F.seed!(profile)
      signals = [%{"activityRecord" => record(1_768_519_920 + offset, "window")}]
      File.write!(path, Jason.encode!(signals))
      assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok
      [[motion]] = F.query("SELECT motion_data FROM points WHERE id=56306")

      if offset <= 60,
        do: assert(motion["activityRecord"] == hd(signals)["activityRecord"]),
        else:
          assert(motion == List.last(profile["before"]["points"] |> Enum.take(6))["motion_data"])
    end

    F.seed!(profile)
    F.query("ALTER TABLE points ALTER COLUMN motion_data DROP NOT NULL")
    F.query("UPDATE points SET motion_data=NULL WHERE id=56304")
    signals = [record(1_768_519_801, "near_first"), record(1_768_519_801, "equal_later")]
    File.write!(path, Jason.encode!(Enum.map(signals, &%{"activityRecord" => &1})))
    assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok

    assert F.query("SELECT motion_data FROM points WHERE id=56304") == [
             [%{"activityRecord" => hd(signals)}]
           ]

    assert F.query("SELECT motion_data FROM points WHERE id=56303") == [
             [profile["before"]["points"] |> Enum.at(2) |> Map.fetch!("motion_data")]
           ]

    F.query("UPDATE points SET motion_data='0'::jsonb WHERE id=56304")
    File.write!(path, Jason.encode!([%{"activityRecord" => record(1_768_519_800, "scalar")}]))
    assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok

    assert F.query("SELECT motion_data FROM points WHERE id=56304") == [
             [[0, %{"activityRecord" => record(1_768_519_800, "scalar")}]]
           ]

    F.query("DELETE FROM points WHERE import_id=987101")
    sentinel = F.snapshot()
    assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok
    assert F.snapshot() == sentinel

    for bytes <- [
          "{}",
          "null",
          "{\"rawSignals\":false}",
          "{\"rawSignals\":[],\"rawSignals\":null}"
        ] do
      File.write!(path, bytes)
      assert Phone.run(ScratchRepo, 987_101, path, F.context()) == :ok
      assert F.snapshot() == sentinel
    end
  end

  defp record(timestamp, label),
    do: %{
      "timestamp" => timestamp,
      "extra" => label,
      "nullable" => nil,
      "probableActivities" => []
    }
end
