defmodule Dawarich.RawData.ArchivesDestroyTest do
  use Dawarich.JobsCase

  alias Dawarich.{ScratchRepo, Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.Archives

  test "deletes the archive, its attachment, blob and object whether or not a journal row exists" do
    Wave6Fixtures.reset!()
    storage = Wave6Fixtures.local_storage!()
    user = Wave6Fixtures.user!()

    ids =
      for chunk <- [1, 2] do
        id = Wave6Archives.archive!(user, %{"chunk_number" => chunk})
        Wave6Archives.attach!(storage, id, Archives.storage_key(user, 2020, 1, chunk), "bytes")
        id
      end

    ScratchRepo.query!(
      "INSERT INTO phoenix.raw_data_archive_chunks (archive_id, user_id, storage_key, phase) VALUES ($1, $2, $3, 'attached')",
      [List.last(ids), user, Archives.storage_key(user, 2020, 1, 2)]
    )

    assert Enum.map(ids, &Archives.destroy(ScratchRepo, storage, &1)) == [:ok, :ok]

    assert rows(
             "SELECT (SELECT count(*) FROM points_raw_data_archives) + (SELECT count(*) FROM active_storage_blobs) + (SELECT count(*) FROM phoenix.raw_data_archive_chunks)"
           ) == [[0]]

    assert Wave6Archives.object_paths(storage) == []
  end
end
