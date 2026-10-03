defmodule Dawarich.Imports.NormalWriterOracleTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Imports.BulkWriter
  @stamp ~N[2026-01-01 00:00:00]
  @inputs Path.expand("../../fixtures/imports/normal_writer_inputs.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()
          |> Map.new(&{&1["name"], &1})
  @cases Path.expand("../../fixtures/imports/rails_normal_writer_oracle.json", __DIR__)
         |> File.read!()
         |> Jason.decode!()
  @columns ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)

  setup do
    user = user!()

    {1, [%{id: id}]} =
      Repo.insert_all(
        "imports",
        [%{user_id: user, name: "normal.rec", source: 1, created_at: @stamp, updated_at: @stamp}],
        returning: [:id]
      )

    %{import: %{id: id, user_id: user}}
  end

  for example <- @cases do
    @example example
    @input Map.fetch!(@inputs, example["name"])
    test "independent Rails persisted oracle: #{example["name"]}", %{import: import} do
      e = @example

      attrs = %{
        lonlat: "POINT(12.4 51.3)",
        timestamp: 1_700_000_000,
        altitude: 12.75,
        altitude_decimal: 12.75,
        velocity: 1.2,
        tracker_id: "normal-oracle",
        import_id: import.id,
        user_id: import.user_id,
        created_at: @stamp,
        updated_at: @stamp
      }

      batch =
        Enum.map(@input["rows"] || [@input["attributes"]], fn row ->
          Map.merge(
            attrs,
            Map.new(row, fn {key, value} -> {String.to_atom(key), decode_tags(value)} end)
          )
        end)

      result =
        try do
          {:ok, BulkWriter.write(batch, import, %{}, Repo)}
        rescue
          error -> {:error, error}
        end

      if e["error"] do
        assert {:error, error} = result
        assert_same_error(error, e["error"])
      else
        assert {:ok, {inserted, _}} = result
        assert inserted == e["inserted"]
      end

      assert Repo.query!("SELECT raw_points,doubles FROM imports WHERE id=$1", [import.id]).rows ==
               [e["counters"]]

      sql =
        Enum.map_join(@columns, ",", fn column ->
          if column == "lonlat", do: "ST_AsText(lonlat::geometry)", else: ~s("#{column}")
        end)

      actual =
        Repo.query!("SELECT #{sql} FROM points WHERE import_id=$1 ORDER BY id", [import.id]).rows
        |> Enum.map(fn values -> Enum.zip(@columns, values) |> Map.new() |> decimals() end)

      assert actual == Enum.map(e["points"], &decimals/1)

      columns =
        ~w(digest tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)

      sources =
        Repo.query!("SELECT #{Enum.join(columns, ",")} FROM point_sources ORDER BY id").rows
        |> Enum.map(&(Enum.zip(columns, &1) |> Map.new()))

      assert sources == e["sources"]

      [[matched]] =
        Repo.query!(
          "SELECT count(*) FROM points p JOIN point_sources s ON s.id=p.source_id WHERE p.import_id=$1",
          [import.id]
        ).rows

      assert matched == length(e["points"])
      commands = commands()

      if e["inserted"] && e["inserted"] > 0 do
        assert [["points.tile_epoch", %{"user_id" => user, "timestamps" => [timestamp]}]] =
                 commands

        assert user == import.user_id
        assert timestamp == hd(batch).timestamp
      else
        assert commands == []
      end
    end
  end

  test "symbolic adapter does not intern untrusted keys" do
    key = "untrusted-" <> Base.encode16(:crypto.strong_rand_bytes(32))
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    wrapped = Dawarich.Imports.NormalCast.symbolic(%{key => [%{key => true}]})
    assert Dawarich.Imports.NormalCast.json_value(wrapped) == %{key => [%{key => true}]}
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
  end

  defp decode_tags(%{"__float__" => name}),
    do: Map.fetch!(%{"Infinity" => :infinity, "-Infinity" => :neg_infinity, "NaN" => :nan}, name)

  defp decode_tags(%{"__bytes__" => hex}), do: Base.decode16!(hex, case: :mixed)

  defp decode_tags(%{"__symbol_pairs__" => pairs}),
    do:
      pairs
      |> Enum.map(fn [key, value] -> {key, decode_tags(value)} end)
      |> Dawarich.Imports.NormalCast.symbolic_hash()

  defp decode_tags(%{"__symbol_hash__" => map}),
    do:
      map
      |> Map.new(fn {key, value} -> {key, decode_tags(value)} end)
      |> Dawarich.Imports.NormalCast.symbolic()

  defp decode_tags(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, decode_tags(value)} end)

  defp decode_tags(list) when is_list(list), do: Enum.map(list, &decode_tags/1)
  defp decode_tags(value), do: value

  defp assert_same_error(error, %{"message" => "PG::" <> _ = message}) do
    [_, class, primary] = Regex.run(~r/\APG::(\w+): ERROR:  (.*)\z/, message)
    assert %Postgrex.Error{postgres: %{code: code, message: ^primary}} = error
    assert Atom.to_string(code) == Macro.underscore(class)
  end

  defp assert_same_error(error, %{"message" => message}),
    do: assert(Exception.message(error) == message)

  defp decimals(row) do
    Enum.reduce(~w(altitude_decimal course course_accuracy), row, fn key, acc ->
      Map.update!(acc, key, fn
        nil -> nil
        %Decimal{} = d -> Decimal.normalize(d)
        value -> value |> Decimal.new() |> Decimal.normalize()
      end)
    end)
  end
end
