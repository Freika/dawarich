defmodule Dawarich.Metrics.ArchiveTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{Archiver, Verifier, Clearer, Restorer}
  @moduletag :capture_log

  defmodule ConcurrentDeleteRepo do
    def query!(sql, params, opts) do
      result = Dawarich.ScratchRepo.query!(sql, params, opts)

      if sql =~ "extract(year FROM to_timestamp(timestamp)" and result.rows != [] do
        Dawarich.ScratchRepo.query!("DELETE FROM points WHERE id=$1", [hd(hd(result.rows))],
          log: false
        )
      end

      result
    end
  end

  setup do
    Wave6Fixtures.reset!()
    start_supervised!(Dawarich.Metrics)

    %{
      storage: Wave6Fixtures.local_storage!(),
      user: Wave6Fixtures.user!(),
      key: Wave6Archives.key()
    }
  end

  test "native archive verify clear and restore emit the existing archive metric families", ctx do
    for n <- 1..3, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})
    assert {:continue, 0} = Archiver.pass(ScratchRepo, ctx.storage, ctx.key, ctx.user, 0)
    [[id]] = rows("SELECT id FROM points_raw_data_archives")
    assert :ok = Verifier.verify(ScratchRepo, ctx.storage, ctx.key, id)
    assert Clearer.clear_month(ScratchRepo, ctx.user, 2020, 1) == 3

    assert %{restored: 3} =
             Restorer.restore_month(ScratchRepo, ctx.storage, ctx.key, ctx.user, 2020, 1)

    rows("UPDATE points_raw_data_archives SET point_count=4")
    assert {:error, :count_mismatch} = Verifier.verify(ScratchRepo, ctx.storage, ctx.key, id)
    rows("UPDATE points SET raw_data_archived=false,raw_data_archive_id=NULL")

    assert :done =
             Archiver.pass(ScratchRepo, ctx.storage, ctx.key, ctx.user, 0,
               before_verify: fn _ -> raise "synthetic archive failure" end
             )

    body = Dawarich.Metrics.scrape()

    for operation <- ["archive", "verify", "clear", "restore"] do
      assert body =~
               ~s(dawarich_archive_operations_total{operation="#{operation}",status="success"} 1)
    end

    assert body =~ ~s(dawarich_archive_operations_total{operation="archive",status="failure"} 1)

    for operation <- ["added", "removed", "restored"] do
      assert body =~ ~s(dawarich_archive_points_total{operation="#{operation}"} 3)
    end

    assert body =~ "dawarich_archive_compression_ratio_count 1"
    assert body =~ "dawarich_archive_size_bytes_count 1"
    assert body =~ ~s(dawarich_archive_verification_duration_seconds_count{status="failure"} 1)
    assert body =~ ~s(dawarich_archive_verification_failures_total{check="count_mismatch"} 1)
    refute body =~ "synthetic archive failure"
    refute body =~ ctx.storage.root
    assert :done = Archiver.pass(ConcurrentDeleteRepo, ctx.storage, ctx.key, ctx.user, 0)
    mismatch = Dawarich.Metrics.scrape()
    assert mismatch =~ ~s(dawarich_archive_count_mismatches_total{month="1",year="2020"} 1)
    assert mismatch =~ ~s(dawarich_archive_count_difference{user_id="#{ctx.user}"} 1)

    assert {:continue, cursor} =
             Archiver.pass(ScratchRepo, ctx.storage, ctx.key, ctx.user, 0,
               before_flag: fn -> rows("UPDATE points SET raw_data='{}'") end
             )

    assert cursor > 0

    assert Dawarich.Metrics.scrape() =~
             ~s(dawarich_archive_operations_total{operation="archive",status="skipped"} 1)
  end
end
