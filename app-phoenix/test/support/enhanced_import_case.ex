defmodule Dawarich.EnhancedImportCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.Geocoding.HookRepo
  alias Dawarich.{Redis, ScratchRepo, Storage, Wave5bFixtures}

  @dir "test/fixtures/enhanced_import"
  @places "SELECT user_id, name, latitude::text, longitude::text, ST_AsText(lonlat), city, country, source, " <>
            "import_id, demo, note, geodata::text, name_locked_at IS NOT NULL, reverse_geocoded_at IS NOT NULL " <>
            "FROM places ORDER BY id"
  @place_keys ~w(user_id name latitude longitude lonlat_wkt city country source import_id demo note geodata
                 name_locked_at reverse_geocoded_at)

  using do
    quote do
      use Dawarich.JobsCase
      import Dawarich.EnhancedImportCase
      alias Dawarich.Geocoding.HookRepo

      setup do: Dawarich.EnhancedImportCase.setup!()
    end
  end

  def setup! do
    truncate!()
    ExUnit.Callbacks.start_supervised!(hd(Redis.child_specs()))
    {:ok, "OK"} = Redis.command(["FLUSHDB"])
    HookRepo.clear_hook()
    ExUnit.Callbacks.on_exit(&HookRepo.clear_hook/0)
    root = Path.join(System.tmp_dir!(), "w5b-extract-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)
    %{storage: %{service: "local", root: root}}
  end

  def truncate! do
    ScratchRepo.query!(
      "TRUNCATE users, imports, places, tags, taggings, visits, place_visits, notes, tracks, " <>
        "active_storage_attachments, active_storage_blobs, phoenix.rails_commands RESTART IDENTITY CASCADE",
      [],
      log: false
    )

    :ok
  end

  def fixture(name), do: Wave5bFixtures.read!(Path.join(@dir, name <> ".json"))
  def fixture_paths, do: @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()

  def load!(name), do: Wave5bFixtures.load!(ScratchRepo, Path.join(@dir, name <> ".json")).fixture

  def tmp!(storage), do: Storage.tmp_dir!(storage, "t-#{System.unique_integer([:positive])}")

  def attach!(storage, file) do
    key = Storage.generate_key()
    path = Storage.disk_path(storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Base.decode64!(file["base64"]))

    [[blob_id]] =
      rows(
        "INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, " <>
          "checksum, created_at) VALUES ($1, $2, $3, '{}', 'local', $4, $5, now()) RETURNING id",
        [key, file["filename"], file["content_type"], file["byte_size"], file["checksum"]]
      )

    rows(
      "INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at) " <>
        "VALUES ('file', 'Import', $1, $2, now())",
      [file["import_id"], blob_id]
    )

    :ok
  end

  def item(expected) do
    %{
      external_place_id: expected["external_place_id"],
      name: expected["name"],
      latitude: expected["latitude"] * 1.0,
      longitude: expected["longitude"] * 1.0,
      semantic_type: expected["semantic_type"],
      tag_name: expected["tag_name"],
      tag_color: expected["tag_color"]
    }
  end

  def places, do: Enum.map(rows(@places), &Map.new(Enum.zip(@place_keys, &1)))

  def expected_places(expected) do
    for place <- expected["places"] do
      place
      |> Map.take(@place_keys)
      |> Map.update!("name_locked_at", &(&1 != nil))
      |> Map.update!("reverse_geocoded_at", &(&1 != nil))
    end
  end

  def tags,
    do:
      rows("SELECT user_id, name, color, privacy_radius_meters, demo FROM tags ORDER BY id")
      |> Enum.map(&Map.new(Enum.zip(~w(user_id name color privacy_radius_meters demo), &1)))

  def expected_tags(expected), do: Enum.map(expected["tags"], &Map.drop(&1, ["id"]))

  def taggings do
    rows(
      "SELECT t.name, p.name, ST_AsText(p.lonlat), g.taggable_type FROM taggings g " <>
        "JOIN tags t ON t.id = g.tag_id JOIN places p ON p.id = g.taggable_id ORDER BY g.id"
    )
  end

  def expected_taggings(expected) do
    tags = Map.new(expected["tags"], &{&1["id"], &1["name"]})
    places = Map.new(expected["places"], &{&1["id"], {&1["name"], &1["lonlat_wkt"]}})

    for t <- expected["taggings"] do
      {name, wkt} = places[t["taggable_id"]]
      [tags[t["tag_id"]], name, wkt, t["taggable_type"]]
    end
  end

  def import_state(id) do
    [[status, payload, raw]] =
      rows(
        "SELECT additional_data_extraction_status, additional_data_extraction, raw_data::text " <>
          "FROM imports WHERE id = $1",
        [id]
      )

    {status, payload, raw}
  end

  def stamp?(value), do: is_binary(value) and value =~ ~r/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/

  def kinds do
    for [kind, payload] <- rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id"),
        do: %{"kind" => kind, "payload" => payload}
  end

  def with_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end
  end

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
