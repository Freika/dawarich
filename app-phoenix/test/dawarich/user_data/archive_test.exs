defmodule Dawarich.UserData.ArchiveTest do
  use ExUnit.Case, async: false
  alias Dawarich.Imports.GpxArchive.{Directory, Error}
  alias Dawarich.Imports.JsonStream
  alias Dawarich.UserData.{Archive, Jsonl, Paths, Versions}
  alias Dawarich.Test.UserDataSeeds

  @fixtures Path.expand("../../fixtures/user_data", __DIR__)

  @tag :tmp_dir
  test "user-data paths version precedence and output caps match Rails", %{tmp_dir: dir} do
    path = zip!(dir, "unsafe", UserDataSeeds.entries("unsafe_paths"))

    File.open!(path, [:read, :binary], fn file ->
      assert_raise Error, "Unsafe ZIP entry path", fn -> Directory.read!(file, []) end
    end)

    Archive.with_directory(path, %{}, fn extracted ->
      assert Versions.detect(extracted) == 2

      assert Jsonl.decode!(File.read!(Path.join(extracted, "settings.jsonl"))) ==
               %{"timezone" => "Europe/Berlin", "gps_filtering_enabled" => false}

      refute File.exists?(Path.join(extracted, "outside.jsonl"))
      refute File.exists?(Path.join(extracted, "files/unwanted"))
      files = Versions.manifest(extracted)["files"]["points"]

      assert Enum.map(files, &Paths.relative(extracted, &1)) ==
               [
                 nil,
                 nil,
                 Path.join(extracted, "missing.jsonl"),
                 Path.join(extracted, "points/ok.jsonl")
               ]

      send(self(), {:extracted, extracted})
    end)

    assert_received {:extracted, extracted}
    refute File.exists?(extracted)
    assert Paths.sanitize("\\\\/settings.jsonl") == "settings.jsonl"
    assert Paths.sanitize("foo..bar") == nil
    assert Paths.relative(dir, "../escape") == nil
    assert Paths.relative(dir, "/tmp/synthetic.jsonl") == nil
    assert Paths.relative(dir, "nested/../data.json") == Path.join(dir, "nested/../data.json")
    assert Paths.attachment(dir, "../../synthetic.json") == Path.join(dir, "synthetic.json")
    assert Paths.attachment(dir, "..") == nil
    assert Paths.attachment(dir, " ") == nil

    for {fixture, version} <- [
          {"manifest_precedence", 3},
          {"manifest_string_version", "2"},
          {"invalid_manifest", 2},
          {"v1", 1}
        ] do
      zip = zip!(dir, fixture, UserDataSeeds.entries(fixture))
      Archive.with_directory(zip, %{}, &assert(Versions.detect(&1) == version))
    end

    assert_raise Versions.UnsupportedFormatError,
                 "Unknown export format: neither manifest.json nor data.json found",
                 fn -> Versions.detect(dir) end

    assert_raise Jason.DecodeError, fn ->
      Versions.manifest(Path.join(@fixtures, "invalid_manifest/entries"))
    end

    payload = :binary.copy("x", 100_000)
    capped = zip!(dir, "capped", [{"data.json", payload}])
    bytes = File.read!(capped)
    [{local, _}] = :binary.matches(bytes, <<0x04034B50::little-32>>)
    [{central, _}] = :binary.matches(bytes, <<0x02014B50::little-32>>)
    bytes = patch_size(bytes, local + 22, 8) |> patch_size(central + 24, 8)
    File.write!(capped, bytes)

    assert_raise Error, "ZIP entry exceeds extracted byte budget", fn ->
      Archive.with_directory(capped, %{}, fn _ -> flunk("overflow admitted") end,
        max_entry_bytes: 8
      )
    end
  end

  @tag :tmp_dir
  test "user-data JSONL preserves blank and invalid line disposition", %{tmp_dir: dir} do
    path = Path.join(dir, "rows.jsonl")
    File.write!(path, " \t\r\n\x00{\"flag\":false,\"nullable\":null}\x00\n\nnull\nfalse\n[]\n")

    assert Jsonl.reduce(path, [], fn row, rows -> rows ++ [row] end) ==
             [%{"flag" => false, "nullable" => nil}, nil, false, []]

    for fixture <- [
          "invalid_jsonl_root/entries/areas.jsonl",
          "invalid_jsonl_monthly/entries/points/bad.jsonl"
        ] do
      assert_raise JsonStream.Error, fn ->
        Jsonl.reduce(Path.join(@fixtures, fixture), [], fn row, rows -> [row | rows] end)
      end
    end

    for fixture <- ["v1", "v1_reversed"] do
      source = Path.join(@fixtures, fixture <> "/entries/data.json")

      {:object, pairs} =
        JsonStream.reduce(
          source,
          nil,
          fn
            {:value, [], value, _, _}, _ -> value
            _, acc -> acc
          end,
          fn _ -> true end
        )

      sections = ~w(settings areas imports exports trips stats notifications counts)

      expected =
        Enum.flat_map(pairs, fn
          {"places", rows} -> Enum.map(rows, &{:row, "places", Jsonl.value(&1)})
          {key, value} -> if key in sections, do: [{:section, key, Jsonl.value(value)}], else: []
        end)

      expected =
        expected ++
          Enum.flat_map(["visits", "points"], fn section ->
            Enum.map(Map.get(Map.new(pairs), section, []), &{:row, section, Jsonl.value(&1)})
          end)

      actual = Versions.reduce_v1(source, %{}, [], fn event, acc -> acc ++ [event] end)
      assert actual == expected
      assert List.last(actual) |> elem(1) == "points"

      assert Enum.find(actual, &match?({:section, "settings", _}, &1))
             |> elem(2)
             |> Map.fetch!("gps_filtering_enabled") == false
    end

    File.write!(
      path,
      ~s({"points":[null,false,{},42],"places":[null,false,{}],"visits":[null,false,{}]})
    )

    assert Versions.reduce_v1(path, %{}, [], fn event, acc -> acc ++ [event] end) ==
             [
               {:row, "places", %{}},
               {:row, "visits", %{}},
               {:row, "points", %{}},
               {:row, "points", 42}
             ]

    File.write!(path, ~s({"points":[{},invalid]}))

    assert_raise JsonStream.Error, fn ->
      Versions.reduce_v1(path, %{}, nil, fn _, acc -> acc end)
    end
  end

  defp zip!(dir, tag, entries) do
    replacements =
      Enum.with_index(entries)
      |> Enum.map(fn {{name, bytes}, index} ->
        safe =
          String.duplicate("z", byte_size(name) - byte_size(Integer.to_string(index))) <>
            Integer.to_string(index)

        {safe, name, bytes}
      end)

    {:ok, {_, archive}} =
      :zip.create(
        ~c"fixture.zip",
        Enum.map(replacements, fn {safe, _, bytes} -> {String.to_charlist(safe), bytes} end),
        [:memory]
      )

    archive =
      Enum.reduce(replacements, archive, fn {safe, name, _}, bytes ->
        :binary.replace(bytes, safe, name, [:global])
      end)

    path = Path.join(dir, tag <> ".zip")
    File.write!(path, archive)
    path
  end

  defp patch_size(bytes, offset, size) do
    <<head::binary-size(offset), _::32, tail::binary>> = bytes
    head <> <<size::little-32>> <> tail
  end
end
