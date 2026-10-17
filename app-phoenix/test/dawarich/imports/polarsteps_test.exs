defmodule Dawarich.Imports.PolarstepsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Polarsteps
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  setup do
    Dawarich.Ingest.Sources.forget()
    :ok
  end

  test "polarsteps keeps nested coordinates and numeric-string time" do
    for path <- Path.wildcard(Path.join(@dir, "polarsteps_import_*.json")),
        not String.ends_with?(path, ".input.json"),
        Path.basename(path) != "polarsteps_import_1001.json" do
      c = NormalFormats.seed!(Path.basename(path, ".json"), ScratchRepo)

      if c.expected["legacy"] do
        assert {:error, :legacy_checked} =
                 ScratchRepo.transaction(fn ->
                   ScratchRepo.query!(
                     "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                   )

                   Dawarich.Ingest.Sources.forget()
                   run(c)
                   ScratchRepo.rollback(:legacy_checked)
                 end)

        Dawarich.Ingest.Sources.forget()
      else
        run(c)
      end
    end
  end

  test "polarsteps reports rounded-up final batch progress" do
    c = NormalFormats.seed!("polarsteps_import_1001", ScratchRepo)

    seen = fn fun ->
      result = fun.()
      send(self(), {:progress, rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])})
      result
    end

    assert :ok =
             Polarsteps.call(c.path, c.import, %{
               c.context
               | fence: seen,
                 now: fn -> c.context.now end
             })

    Dawarich.Test.NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
    assert_receive {:progress, [[0]]}
    assert_receive {:progress, [[1000]]}
    assert_receive {:progress, [[1000]]}
    assert_receive {:progress, [[1000]]}
    assert_receive {:progress, [[2000]]}
    assert_receive {:progress, [[2000]]}
  end

  defp run(c) do
    if c.expected["error"] do
      assert_raise Dawarich.Imports.JsonStream.Error, fn ->
        Polarsteps.call(c.path, c.import, c.context)
      end
    else
      assert :ok = Polarsteps.call(c.path, c.import, c.context)
    end

    Dawarich.Test.NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
