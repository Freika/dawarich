defmodule Dawarich.Exports.ZipTest do
  use ExUnit.Case, async: true

  alias Dawarich.Exports.Zip

  @rails "test/fixtures/wave2/rails_geojson.zip" |> File.read!()
  @payload "test/fixtures/wave2/points.json"
           |> File.read!()
           |> Jason.decode!()
           |> get_in(["exports", "Etc/UTC", "geojson"])

  setup do
    dir = Path.join(System.tmp_dir!(), "w2-zip-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp zip!(dir, payload, name) do
    source = Path.join(dir, "payload")
    File.write!(source, payload)
    zip = Path.join(dir, "export.zip")
    Zip.write!(zip, source, name)
    File.read!(zip)
  end

  test "Rails' payload zips to within 10 % of Rails' archive and reads back byte for byte", %{
    dir: dir
  } do
    assert {:ok, [{~c"wave2 export", @payload}]} = :zip.unzip(@rails, [:memory])

    zip = zip!(dir, @payload, "wave2 export")

    assert abs(byte_size(zip) - byte_size(@rails)) <= byte_size(@rails) * 0.1
    assert {:ok, [{~c"wave2 export", @payload}]} = :zip.unzip(zip, [:memory])
    assert <<0x50, 0x4B, 3, 4, _version::16, _flags::16, 8::little-16, _::binary>> = zip
  end

  test "a payload of many chunks keeps its bytes and CRC", %{dir: dir} do
    payload = for i <- 1..40_000, into: "", do: "#{i * 7919},"

    zip = zip!(dir, payload, "points.json")

    assert {:ok, [{~c"points.json", ^payload}]} = :zip.unzip(zip, [:memory])
    assert [{:zip_file, ~c"points.json", info, _, _, _}] = elem(:zip.list_dir(zip), 1) |> tl()
    assert elem(info, 1) == byte_size(payload)
  end

  test "the entry name is the export name as rubyzip writes it: long names and .. segments too",
       %{
         dir: dir
       } do
    long = "trip_" <> String.duplicate("a", 300) <> "_2026-03-29.json"

    for name <- [long, "../../escaped", "zürich tour.gpx"] do
      zip = zip!(dir, "{}", name)
      assert {:ok, [{_entry, "{}"}]} = :zip.unzip(zip, [:memory])
      assert <<_::binary-26, size::little-16, _::16, ^name::binary-size(size), _::binary>> = zip
    end

    assert File.ls!(dir) |> Enum.sort() == ["export.zip", "payload"]
  end

  test "a leading / or a name over 65,535 bytes is refused like rubyzip", %{dir: dir} do
    for name <- ["/etc/passwd", String.duplicate("a", 65_536)] do
      assert_raise ArgumentError, "invalid zip entry name", fn -> zip!(dir, "{}", name) end
    end
  end

  test "a central directory at or past 4 GiB gets the zip64 end records" do
    cd_offset = 5_000_000_000

    assert <<0x06064B50::little-32, 44::little-64, _made_by::16, 45::little-16, 0::32, 0::32,
             1::little-64, 1::little-64, 97::little-64, ^cd_offset::little-64,
             0x07064B50::little-32, 0::32, locator::little-64, 1::little-32,
             0x06054B50::little-32, 0::32, 1::little-16, 1::little-16, 97::little-32,
             0xFFFFFFFF::little-32, 0::16>> = IO.iodata_to_binary(Zip.trailer(cd_offset, 97))

    assert locator == cd_offset + 97

    assert IO.iodata_to_binary(Zip.trailer(1_401, 87)) ==
             <<0x06054B50::little-32, 0::32, 1::little-16, 1::little-16, 87::little-32,
               1_401::little-32, 0::16>>
  end
end
