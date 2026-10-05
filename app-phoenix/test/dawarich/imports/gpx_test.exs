defmodule Dawarich.Imports.GpxTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.Gpx

  @fixtures Path.expand("../../fixtures/gpx", __DIR__)

  setup_all do
    path =
      Path.join(
        System.tmp_dir!(),
        "gpx-namespaces-#{System.pid()}-#{System.unique_integer([:positive])}.gpx"
      )

    on_exit(fn -> File.rm!(path) end)

    File.open!(path, [:write, :binary, :raw], fn io ->
      IO.binwrite(io, "<gpx><trk><trkseg>")

      1..100_000
      |> Stream.map(fn i ->
        "<trkpt xmlns:p#{i}=\"urn:#{i}\" lat=\"1\" lon=\"2\"><time>2026-01-01T00:00:00Z</time></trkpt>"
      end)
      |> Stream.chunk_every(1_000)
      |> Enum.each(&IO.binwrite(io, &1))

      IO.binwrite(io, "</trkseg></trk></gpx>")
    end)

    %{namespace_path: path}
  end

  test "real Rails SAX fixture output, counts and tracker labels match exactly" do
    oracle = @fixtures |> Path.join("rails_oracle.json") |> File.read!() |> Jason.decode!()

    for row <- oracle do
      {points, counts} =
        Gpx.reduce(Path.join(@fixtures, row["file"]), %{id: 42, name: row["file"]}, [], fn p,
                                                                                           id,
                                                                                           acc ->
          [%{"point" => p, "tracker_id" => id} | acc]
        end)

      assert Enum.reverse(points) == row["points"], row["file"]
      assert counts == row["counts"], row["file"]
    end
  end

  test "orphan, tracks and segments retain separate literal identities" do
    xml =
      "<gpx>#{point()}<trk><trkseg>#{point()}</trkseg><trkseg>#{point()}</trkseg></trk><trk><trkseg>#{point()}</trkseg></trk></gpx>"

    {rows, counts} = collect(xml)

    assert Enum.map(rows, &elem(&1, 1)) == [
             "import-42-orphan",
             "import-42-trk-0-seg-0",
             "import-42-trk-0-seg-1",
             "import-42-trk-1-seg-0"
           ]

    assert counts == %{"trackpoints_seen" => 4}
  end

  test "src supersedes name and is stable when import filename changes" do
    xml =
      "<gpx><trk><src>Garmin Forerunner 245</src><name>Morning Run</name><trkseg>#{point()}</trkseg></trk></gpx>"

    {[{_, id}], _} = collect(xml, "a.gpx")
    {[{_, other}], _} = collect(xml, "b.gpx")
    assert id == other
    assert String.starts_with?(id, "gpx-")
    assert String.ends_with?(id, "-trk-0-seg-0")

    {[{_, name_id}], _} =
      collect(String.replace(xml, "<src>Garmin Forerunner 245</src>", ""), "a.gpx")

    {[{_, other_name_id}], _} =
      collect(String.replace(xml, "<src>Garmin Forerunner 245</src>", ""), "b.gpx")

    refute name_id == id
    refute name_id == other_name_id
  end

  test "nested metadata text is ignored, repeated fields overwrite, CDATA ignored" do
    xml =
      "<gpx><trk><name> Morning <b>ignored</b> Run </name><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>1</ele><ele>2</ele><time>2026-01-01T00:00:00Z</time><name><![CDATA[ignored]]>plain</name><extensions><g:speed xmlns:g=\"urn:g\">3.4</g:speed></extensions></trkpt></trkseg></trk></gpx>"

    {[{p, id}], _} = collect(xml)

    assert p == %{
             "lat" => "1",
             "lon" => "2",
             "ele" => "2",
             "time" => "2026-01-01T00:00:00Z",
             "name" => "plain",
             "extensions" => %{"speed" => "3.4"}
           }

    {[{_, other}], _} =
      collect(String.replace(xml, " Morning <b>ignored</b> Run ", "Morning  Run"))

    assert id == other
  end

  test "waypoints and route points counted but never emitted as trackpoints" do
    {[], counts} = collect("<gpx><wpt lat=\"1\" lon=\"2\"/><rte><rtept/></rte></gpx>")
    assert counts == %{"waypoints_seen" => 1, "route_points_seen" => 1}
  end

  test "undeclared namespace prefixes are recovered and counted" do
    xml =
      "<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><extensions><foo:bar>x</foo:bar><baz:qux>y</baz:qux></extensions></trkpt></trkseg></trk></gpx>"

    {[{p, _}], counts} = collect(xml)
    assert p["extensions"] == %{"bar" => "x", "qux" => "y"}
    assert counts == %{"trackpoints_seen" => 1, "parse_errors_seen" => 2}
  end

  for {name, tail} <- [
        {"truncation", "<trkpt>"},
        {"mismatched close", "<trkpt></gpx>"},
        {"unescaped ampersand", "<name>Tom & Jerry</name>"}
      ] do
    test "#{name} raises after a valid point instead of returning partial success" do
      assert_raise ArgumentError, ~r/GPX parse error/, fn ->
        collect("<gpx>#{point()}#{unquote(tail)}")
      end
    end
  end

  test "extra document content raises" do
    assert_raise ArgumentError, ~r/GPX parse error/, fn -> collect("<gpx/> <gpx/>") end
  end

  test "extra document after a continuation boundary raises" do
    assert_raise ArgumentError, ~r/GPX parse error/, fn ->
      collect("<gpx/>" <> String.duplicate(" ", 70_000) <> "<gpx/>")
    end
  end

  test "valid trailing comments and processing instructions survive encoding chunk boundaries" do
    xml = "<gpx/> <!--" <> String.duplicate("Прогулка", 12_000) <> "--> <?done yes?>"
    assert {[], %{}} == collect(xml)
    utf16 = <<254, 255>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :big})
    assert {[], %{}} == collect(utf16)
  end

  test "a trailing closing tag cannot close the tail validation wrapper" do
    assert_raise ArgumentError, ~r/GPX parse error/, fn -> collect("<gpx/></tail>") end
  end

  test "undefined attribute namespace prefixes count as recoverable errors" do
    {[{p, _}], counts} = collect("<gpx><trkpt foo:device=\"a\" baz:kind=\"b\"/></gpx>")
    assert p == %{"device" => "a", "kind" => "b"}
    assert counts == %{"trackpoints_seen" => 1, "parse_errors_seen" => 2}
  end

  test "callback exceptions retain their type and message" do
    path = temp("<gpx>#{point()}</gpx>")

    assert_raise RuntimeError, "writer lost connection", fn ->
      Gpx.reduce(path, %{id: 42, name: "a.gpx"}, nil, fn _, _, _ ->
        raise "writer lost connection"
      end)
    end
  end

  test "UTF8 BOM overrides misleading encoding declaration and leading junk is skipped" do
    xml = "<?xml version=\"1.0\" encoding=\"utf-16\"?><gpx>#{point()}</gpx>"
    assert {[{p, _}], _} = collect(<<239, 187, 191>> <> xml)
    assert p["lat"] == "1"
    assert {[{same, _}], _} = collect("junk\n<gpx>#{point()}</gpx>")
    assert p == same
  end

  for endian <- [:big, :little] do
    test "UTF16 #{endian} across continuation boundaries preserves unicode and points" do
      xml =
        "<?xml version=\"1.0\" encoding=\"utf-16\"?><gpx><trk><name>Прогулка</name><trkseg>#{String.duplicate(point(), 800)}</trkseg></trk></gpx>"

      bytes = :unicode.characters_to_binary(xml, :utf8, {:utf16, unquote(endian)})
      bom = if unquote(endian) == :big, do: <<254, 255>>, else: <<255, 254>>
      {rows, counts} = collect(bom <> bytes)
      assert length(rows) == 800
      assert counts == %{"trackpoints_seen" => 800}
      assert Enum.all?(rows, fn {p, _} -> p["time"] == "2026-01-01T00:00:00Z" end)
    end
  end

  for endian <- [:big, :little] do
    test "UTF32 #{endian} BOM preserves document characters" do
      xml = "<gpx>#{point()}</gpx>"
      bom = if unquote(endian) == :big, do: <<0, 0, 254, 255>>, else: <<255, 254, 0, 0>>

      {rows, counts} =
        collect(bom <> :unicode.characters_to_binary(xml, :utf8, {:utf32, unquote(endian)}))

      assert [
               {%{"lat" => "1", "lon" => "2", "time" => "2026-01-01T00:00:00Z"},
                "import-42-orphan"}
             ] == rows

      assert counts == %{"trackpoints_seen" => 1}
    end
  end

  test "ISO8859-1 declaration converts unicode metadata without namespace errors" do
    xml =
      "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><gpx><trk xml:lang=\"fr\"><name>Café</name><trkseg>#{point()}</trkseg></trk></gpx>"

    {rows, counts} = collect(:unicode.characters_to_binary(xml, :utf8, :latin1))
    {utf8_rows, _} = collect(String.replace(xml, "ISO-8859-1", "UTF-8"))
    assert rows == utf8_rows
    assert counts == %{"trackpoints_seen" => 1}
  end

  test "callback throw and exit propagate to caller" do
    path = temp("<gpx>#{point()}</gpx>")

    assert catch_throw(
             Gpx.reduce(path, %{id: 42, name: "a.gpx"}, nil, fn _, _, _ ->
               throw(:writer_abort)
             end)
           ) == :writer_abort

    assert catch_exit(
             Gpx.reduce(path, %{id: 42, name: "a.gpx"}, nil, fn _, _, _ ->
               exit(:writer_shutdown)
             end)
           ) == :writer_shutdown
  end

  test "one point with many small fields cannot bypass the memory budget" do
    fields =
      Enum.map_join(1..3_000, fn i -> "<field#{i}>#{String.duplicate("x", 500)}</field#{i}>" end)

    assert_raise ArgumentError, ~r/point token/, fn ->
      collect("<gpx><trkpt>#{fields}</trkpt></gpx>")
    end
  end

  test "unsupported declarations never silently reinterpret bytes as UTF8" do
    for encoding <- ["UTF-16", "Windows-1251"] do
      xml = "<?xml version=\"1.0\" encoding=\"#{encoding}\"?><gpx>#{point()}</gpx>"
      assert_raise ArgumentError, ~r/encoding/, fn -> collect(xml) end
    end
  end

  test "DTD and external/internal entity definitions fail without callbacks" do
    for declaration <- [
          "<!DOCTYPE gpx SYSTEM 'file:///no-such-secret'>",
          "<!DOCTYPE gpx [<!ENTITY a 'expanded'>]>"
        ] do
      assert_raise ArgumentError, fn -> collect(declaration <> "<gpx>#{point()}</gpx>") end
    end
  end

  test "deep XML rejected before excessive recursion" do
    assert_raise ArgumentError, ~r/depth/, fn ->
      collect("<gpx>" <> String.duplicate("<n>", 70) <> String.duplicate("</n>", 70) <> "</gpx>")
    end
  end

  test "huge quoted attributes, comments, CDATA and text rejected while streaming" do
    big = String.duplicate(">", 1_048_577)

    for inner <- [
          "<n value=\"#{big}\"/>",
          "<!--#{big}-->",
          "<![CDATA[#{big}]]>",
          String.duplicate("x", 1_048_577)
        ] do
      assert_raise ArgumentError, ~r/token/, fn -> collect("<gpx>#{inner}</gpx>") end
    end
  end

  test "more than a continuation block of points reduces without accumulating them" do
    path =
      temp([
        "<gpx><trk><trkseg>",
        Stream.map(1..5_500, fn _ -> point() end) |> Enum.to_list(),
        "</trkseg></trk></gpx>"
      ])

    {count, counts} = Gpx.reduce(path, %{id: 42, name: "large.gpx"}, 0, fn _, _, n -> n + 1 end)
    assert count == 5_500
    assert counts == %{"trackpoints_seen" => 5_500}
  end

  test "unique namespace declarations do not accumulate for the whole large file", %{
    namespace_path: path
  } do
    :erlang.garbage_collect()

    {{count, peak}, counts} =
      Gpx.reduce(path, %{id: 42, name: "large.gpx"}, {0, 0}, fn _, _, {n, peak} ->
        bytes = if rem(n, 100) == 0, do: elem(:erlang.process_info(self(), :memory), 1), else: 0
        {n + 1, max(peak, bytes)}
      end)

    assert count == 100_000
    assert counts == %{"trackpoints_seen" => 100_000}
    assert peak < 16_777_216, "parser process retained #{peak} bytes"
  end

  test "ordinary encoding attributes never choose the document codec" do
    for encoding <- ["base64", "ISO-8859-1"] do
      xml =
        "<gpx><trkpt><name>Café</name><extensions><value encoding=\"#{encoding}\">x</value></extensions></trkpt></gpx>"

      {[{point, _}], counts} = collect(xml)
      assert point["name"] == "Café"
      assert point["extensions"] == %{"value" => %{"encoding" => encoding}}
      assert counts == %{"trackpoints_seen" => 1}
    end
  end

  test "supported encoding in a long declaration beyond the first continuation is honored" do
    xml =
      "<?xml version=\"1.0\"" <>
        String.duplicate(" ", 70_000) <>
        "encoding=\"ISO-8859-1\"?><gpx><trkpt><name>Café</name></trkpt></gpx>"

    {[{point, _}], counts} = collect(:unicode.characters_to_binary(xml, :utf8, :latin1))
    assert point["name"] == "Café"
    assert counts == %{"trackpoints_seen" => 1}
  end

  test "references after root are fatal even when they decode to whitespace" do
    for gap <- ["", String.duplicate(" ", 70_000)], reference <- ["&#32;", "&#x9;"] do
      assert_raise ArgumentError, ~r/GPX parse error/, fn ->
        collect("<gpx>#{point()}</gpx>" <> gap <> reference)
      end
    end
  end

  test "metadata budgets do not accumulate across completed empty tracks" do
    tracks = String.duplicate("<trk><name>#{String.duplicate("x", 500)}</name></trk>", 2_100)
    {rows, counts} = collect("<gpx>#{tracks}<trk><trkseg>#{point()}</trkseg></trk></gpx>")

    assert [
             {%{"lat" => "1", "lon" => "2", "time" => "2026-01-01T00:00:00Z"},
              "import-42-trk-2100-seg-0"}
           ] == rows

    assert counts == %{"trackpoints_seen" => 1}
  end

  defp point, do: "<trkpt lat=\"1\" lon=\"2\"><time>2026-01-01T00:00:00Z</time></trkpt>"

  defp collect(xml, name \\ "a.gpx") do
    {rows, counts} =
      Gpx.reduce(temp(xml), %{id: 42, name: name}, [], fn p, id, acc -> [{p, id} | acc] end)

    {Enum.reverse(rows), counts}
  end

  defp temp(xml) do
    path = Path.join(System.tmp_dir!(), "gpx-parser-#{System.unique_integer([:positive])}.xml")
    File.write!(path, xml)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
