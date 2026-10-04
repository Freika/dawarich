defmodule Dawarich.Imports.TcxTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Tcx
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "tcx singleton multiple tracks and escaped ampersands match Rails" do
    for path <- Path.wildcard(Path.join(@dir, "tcx_import_*.json")),
        not String.ends_with?(path, ".input.json"),
        not String.ends_with?(path, "_missing.json") do
      Dawarich.JobsCase.reset!(ScratchRepo)
      Dawarich.Ingest.Sources.forget()
      c = NormalFormats.seed!(Path.basename(path, ".json"), ScratchRepo)
      c = %{c | context: %{c.context | altitude_decimal?: c.expected["legacy"] != true}}

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
      else
        run(c)
      end
    end
  end

  test "tcx missing coordinates or time are skipped before batching" do
    c = NormalFormats.seed!("tcx_import_missing", ScratchRepo)
    run(c)
  end

  defp run(c) do
    if c.expected["error"] do
      assert_raise ArgumentError, fn -> Tcx.call(c.path, c.import, c.context) end
    else
      assert :ok = Tcx.call(c.path, c.import, c.context)
    end

    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
