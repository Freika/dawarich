defmodule Dawarich.EnhancedImport.SourceFileTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.SourceFile

  defp fetch!(storage, import_id),
    do: SourceFile.fetch!(ScratchRepo, import_id, storage, tmp!(storage))

  defp inner(file, name) do
    bytes = Base.decode64!(file["base64"])
    {:ok, entries} = :zip.list_dir(bytes)
    {:zip_file, ^name, _info, _comment, offset, size} = List.keyfind(entries, name, 1)
    <<_::binary-size(^offset + 26), n::little-16, e::little-16, _::binary>> = bytes
    :zlib.unzip(binary_part(bytes, offset + 30 + n + e, size))
  end

  test "manual GPX extraction refuses a key outside the storage root", %{storage: storage} do
    [file] = load!("decimal_cast_waypoint")["files"]
    attach!(storage, file)
    sentinel = Path.join(Path.dirname(storage.root), "sentinel-" <> Ecto.UUID.generate())
    bytes = Base.decode64!(file["base64"])
    File.write!(sentinel, bytes)
    on_exit(fn -> File.rm!(sentinel) end)
    File.mkdir_p!(Path.join(storage.root, "ab/cd/abcd"))
    key = "abcd/../../../../" <> Path.basename(sentinel)
    rows("UPDATE active_storage_blobs SET key=$1", [key])

    assert_raise ArgumentError, "Invalid import storage key", fn ->
      fetch!(storage, file["import_id"])
    end
  end

  test "manual GPX extraction refuses a mismatched stored service", %{storage: storage} do
    [file] = load!("decimal_cast_waypoint")["files"]
    attach!(storage, file)
    rows("UPDATE active_storage_blobs SET service_name='other'")

    assert_raise ArgumentError,
                 "Import blob service does not match configured storage service",
                 fn -> fetch!(storage, file["import_id"]) end
  end

  test "Rails' verification messages", %{storage: storage} do
    fixture = load!("source_file_messages")
    Enum.each(fixture["files"], &attach!(storage, &1))
    ids = Map.new(fixture["input"]["imports"], &{&1["name"], &1["id"]})
    messages = Map.new(fixture["expected"]["cases"], &{&1["name"], &1["message"]})

    for {case_name, import_name} <- [
          {"truncated", "w5b-truncated.gpx"},
          {"checksum_mismatch", "w5b-checksum.gpx"},
          {"zero_byte", "w5b-empty.gpx"},
          {"no_attachment", "w5b-missing.gpx"}
        ] do
      assert_raise RuntimeError, messages[case_name], fn ->
        fetch!(storage, ids[import_name])
      end
    end
  end

  test "a verified plain file is returned as downloaded", %{storage: storage} do
    fixture = load!("envelope_recovery")
    [file | _] = fixture["files"]
    attach!(storage, file)

    assert File.read!(fetch!(storage, file["import_id"])) == Base.decode64!(file["base64"])
  end

  test "single-entry zip unwrap", %{storage: storage} do
    [zipped] = load!("zipped_single_entry")["files"]
    attach!(storage, zipped)

    assert File.read!(fetch!(storage, zipped["import_id"])) == inner(zipped, ~c"favourites.gpx")

    safety = load!("zip_safety")
    [oversized, unsafe] = safety["files"]
    Enum.each(safety["files"], &attach!(storage, &1))

    with_env("ZIP_MAX_EXTRACTED_SIZE", to_string(safety["zip_max_extracted_size"]), fn ->
      assert_raise RuntimeError, "entry exceeds 10 bytes", fn ->
        fetch!(storage, oversized["import_id"])
      end
    end)

    path = fetch!(storage, unsafe["import_id"])
    assert File.read!(path) == inner(unsafe, ~c"../x.gpx")
    assert Path.dirname(Path.dirname(path)) == Path.join(storage.root, ".phoenix-tmp")
    assert Path.wildcard(Path.join(storage.root, "**/x.gpx"), match_dot: true) == []
  end

  test "a zip holding only a directory has no entries", %{storage: storage} do
    [[id]] =
      rows(
        "INSERT INTO imports (user_id, name, source, created_at, updated_at) VALUES (1, 'd.gpx', 4, now(), now()) RETURNING id"
      )

    {:ok, {_, bytes}} = :zip.create(~c"d.zip", [{~c"only/", <<>>}], [:memory])

    attach!(storage, %{
      "import_id" => id,
      "filename" => "d.gpx",
      "content_type" => "application/zip",
      "byte_size" => byte_size(bytes),
      "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
      "base64" => Base.encode64(bytes)
    })

    assert_raise ArgumentError, "zip has no entries", fn -> fetch!(storage, id) end
  end
end
