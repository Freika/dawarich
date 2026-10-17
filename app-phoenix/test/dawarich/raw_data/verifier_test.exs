defmodule Dawarich.RawData.VerifierTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{Storage, Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{ArchiveFormat, Verifier}

  @moduletag :capture_log

  setup_all do: %{key: Wave6Archives.key()}

  setup ctx do
    Wave6Fixtures.reset!()
    columns = if ctx[:rails_user], do: %{"id" => 7}, else: %{}
    %{storage: Wave6Fixtures.local_storage!(), user: Wave6Fixtures.user!(columns)}
  end

  defp verify(ctx, archive_id), do: Verifier.verify(ScratchRepo, ctx.storage, ctx.key, archive_id)

  defp verified?(archive_id),
    do:
      rows("SELECT verified_at IS NOT NULL FROM points_raw_data_archives WHERE id = $1", [
        archive_id
      ]) == [[true]]

  defp object_path(ctx),
    do:
      Storage.disk_path(
        ctx.storage.root,
        "raw_data_archives/#{ctx.user}/2020/01/001.jsonl.gz.enc"
      )

  defp archived!(ctx, raws), do: Wave6Archives.archived!(ctx.storage, ctx.key, ctx.user, raws)

  @tag :rails_user
  test "rails_archive_verifies", %{user: user} = ctx do
    fixture = Wave6Fixtures.load!("raw_archive")

    archive =
      Wave6Archives.archive!(user, %{
        "year" => 2026,
        "month" => 1,
        "point_count" => fixture["point_count"],
        "point_ids_checksum" => fixture["point_ids_checksum"],
        "metadata" => fixture["metadata"]
      })

    Wave6Archives.attach!(ctx.storage, archive, fixture["storage_key"], fixture["message"])

    for point <- fixture["points"] do
      Wave6Fixtures.point!(user, %{
        "id" => point["id"],
        "timestamp" => point["timestamp"],
        "raw_data" => point["raw_data"],
        "raw_data_archived" => true,
        "raw_data_archive_id" => archive
      })
    end

    key = ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => fixture["secret"]})

    assert Verifier.verify(ScratchRepo, ctx.storage, key, archive) == :ok
    assert verified?(archive)
  end

  test "a_verified_archive_that_fails_is_unverified_unless_the_download_failed", ctx do
    {archive, _ids} = archived!(ctx, [%{"n" => 1}, %{"n" => 2}])
    File.write!(object_path(ctx), "corrupted")

    assert verify(ctx, archive) == {:error, :content_checksum_mismatch}
    refute verified?(archive)

    ScratchRepo.query!("UPDATE points_raw_data_archives SET verified_at = now() WHERE id = $1", [
      archive
    ])

    File.rm!(object_path(ctx))

    assert verify(ctx, archive) == {:error, :download_failed}
    assert verified?(archive)
  end

  test "reverifying_keeps_the_first_verified_at", ctx do
    {archive, _ids} = archived!(ctx, [%{"n" => 1}])
    first = ~N[2020-02-01 00:00:00.000000]

    ScratchRepo.query!("UPDATE points_raw_data_archives SET verified_at = $2 WHERE id = $1", [
      archive,
      first
    ])

    assert verify(ctx, archive) == :ok

    assert rows("SELECT verified_at FROM points_raw_data_archives WHERE id = $1", [archive]) ==
             [[first]]
  end

  test "sampled_raw_data_mismatch_fails", ctx do
    {archive, [_first, changed]} = archived!(ctx, [%{"n" => 1}, %{"n" => 2}])
    ScratchRepo.query!("UPDATE points SET raw_data = '{\"n\": 3}' WHERE id = $1", [changed])

    assert verify(ctx, archive) == {:error, :raw_data_mismatch}
  end

  test "sample_skips_relinked_and_cleared_points", ctx do
    {archive, [relinked, cleared, _kept]} =
      archived!(ctx, [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}])

    other = Wave6Archives.archive!(ctx.user, %{"year" => 2019, "month" => 12})

    ScratchRepo.query!(
      "UPDATE points SET raw_data = '{\"n\": 9}', raw_data_archive_id = $1 WHERE id = $2",
      [other, relinked]
    )

    ScratchRepo.query!("UPDATE points SET raw_data = '{}' WHERE id = $1", [cleared])

    assert verify(ctx, archive) == :ok
  end

  test "sample_indices_match_rails" do
    for %{"count" => count, "indices" => indices} <-
          Wave6Fixtures.load!("raw_archive")["sample_indices"] do
      assert Verifier.sample_indices(count) |> Enum.sort() == indices, "count #{count}"
    end
  end

  test "a_marshal_payload_keeps_verification", ctx do
    archive = Wave6Archives.archive!(ctx.user, %{"verified_at" => NaiveDateTime.utc_now()})
    iv = :crypto.strong_rand_bytes(12)
    plaintext = <<4, 8, 73, 34, 6, 97, 6, 58, 6, 69, 84>>

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, ctx.key, iv, plaintext, "", true)

    message = Enum.map_join([ciphertext, iv, tag], "--", &Base.encode64/1)

    Wave6Archives.attach!(
      ctx.storage,
      archive,
      "raw_data_archives/#{ctx.user}/2020/01/001.jsonl.gz.enc",
      message
    )

    assert verify(ctx, archive) == {:error, :unsupported_payload}
    assert verified?(archive)
  end
end
