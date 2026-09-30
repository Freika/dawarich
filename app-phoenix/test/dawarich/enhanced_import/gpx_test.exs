defmodule Dawarich.EnhancedImport.GpxTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.{Gpx, SourceFile}

  @waypoint ~s(<?xml version="1.0"?><gpx><wpt lat="51.3397" lon="12.3731"><name>One</name></wpt></gpx>)

  defp collect(path), do: path |> Gpx.reduce([], &[&1 | &2]) |> Enum.reverse()

  defp write!(storage, xml) do
    path = Path.join(tmp!(storage), "doc.gpx")
    File.write!(path, xml)
    path
  end

  defp expected_items(fixture) do
    single =
      case {fixture["extracted"], fixture["files"]} do
        {items, [file]} when is_list(items) -> [{file["import_id"], items}]
        _ -> []
      end

    grouped =
      for group <- (fixture["expected"] || %{})["extracted"] || [],
          do: {group["import_id"], group["items"]}

    cases =
      for c <- (fixture["expected"] || %{})["cases"] || [],
          c["items"],
          do: {c["import_id"], c["items"]}

    single ++ grouped ++ cases
  end

  test "every GPX fixture yields Rails' places in order", %{storage: storage} do
    checked =
      for path <- fixture_paths(),
          Path.basename(path) != "waypoints_seen_zero.json",
          name = Path.basename(path, ".json"),
          fixture = load!(name),
          {import_id, items} <- expected_items(fixture) do
        file = Enum.find(fixture["files"], &(&1["import_id"] == import_id))
        attach!(storage, file)
        source = SourceFile.fetch!(ScratchRepo, import_id, storage, tmp!(storage))

        assert Enum.all?(items, &(&1["geodata_extras"] == %{})), name
        assert collect(source) == Enum.map(items, &item/1), "#{name} import #{import_id}"
        name
      end

    assert Enum.uniq(checked) ==
             ~w(colour_normalization coordinate_edge_cases decimal_cast_waypoint envelope_recovery
                malformed_documents name_over_limit namespace_and_encoding tag_reuse_and_privacy
                writer_dedup zip_safety zipped_single_entry)
  end

  test "a byte-order mark keeps the document start, so junk after it stops the parse as in Nokogiri",
       %{storage: storage} do
    xml =
      ~s(<?xml version="1.0" encoding="UTF-16"?><gpx><wpt lat="51.34" lon="12.38"><name>Wide</name></wpt></gpx>)

    path =
      write!(storage, <<0xFE, 0xFF>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :big}))

    assert [%{name: "Wide", latitude: 51.34}] = collect(path)

    junk = write!(storage, <<0xEF, 0xBB, 0xBF>> <> "garbage\n" <> @waypoint)
    assert collect(junk) == []
  end

  test "whitespace-only text inside a captured field is kept, as Nokogiri reports it", %{
    storage: storage
  } do
    path =
      write!(
        storage,
        ~s(<gpx><wpt lat="51.3397" lon="12.3731"><name>A<b/> <i/>B</name><type> </type></wpt></gpx>)
      )

    assert [%{name: "A B", semantic_type: nil}] = collect(path)
  end

  test "an internal DTD entity is refused, never expanded", %{storage: storage} do
    path =
      write!(
        storage,
        ~s(<!DOCTYPE gpx [<!ENTITY e "Boom">]><gpx><wpt lat="51.3397" lon="12.3731"><name>&e;</name></wpt></gpx>)
      )

    assert collect(path) == []
  end

  test "a raising callback surfaces its original exception", %{storage: storage} do
    path = write!(storage, @waypoint)

    assert_raise DBConnection.ConnectionError, "connection lost", fn ->
      Gpx.reduce(path, nil, fn _place, _acc ->
        raise DBConnection.ConnectionError, "connection lost"
      end)
    end

    deadlock =
      Postgrex.Error.exception(postgres: %{code: "40P01", severity: "ERROR", message: "deadlock"})

    raised =
      try do
        Gpx.reduce(path, nil, fn _place, _acc -> raise deadlock end)
      rescue
        exception -> exception
      end

    assert raised == deadlock
  end
end
