defmodule Dawarich.Imports.GoogleRecordsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{GoogleRecords, JsonStream}
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  for path <- Path.wildcard(Path.join(@dir, "records_import_*.json")),
      not String.ends_with?(path, ".input.json"),
      Path.basename(path) not in ["records_import_empty.json", "records_import_malformed.json"] do
    @fixture Path.basename(path, ".json")
    test "records storage batches preserve offsets and prior failed-batch effects: #{@fixture}" do
      Dawarich.Ingest.Sources.forget()
      c = NormalFormats.seed!(@fixture, ScratchRepo)

      if c.expected["legacy"] do
        assert {:error, :legacy_checked} =
                 ScratchRepo.transaction(fn ->
                   ScratchRepo.query!(
                     "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                   )

                   Dawarich.Ingest.Sources.forget()
                   run(c, %{c.context | altitude_decimal?: false})
                   ScratchRepo.rollback(:legacy_checked)
                 end)

        Dawarich.Ingest.Sources.forget()
      else
        run(c, %{c.context | now: fn -> c.context.now end})
      end
    end
  end

  test "records invalid document is refused before insertion" do
    for name <- ~w(records_import_empty records_import_malformed) do
      Dawarich.JobsCase.reset!(ScratchRepo)
      c = NormalFormats.seed!(name, ScratchRepo)
      assert_raise JsonStream.Error, fn -> GoogleRecords.call(c.path, c.import, c.context) end
      NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
      assert c.expected["points"] == []
    end
  end

  defp run(c, context) do
    if c.expected["error"] do
      error = assert_raise ArgumentError, fn -> GoogleRecords.call(c.path, c.import, context) end
      assert Exception.message(error) == c.expected["error"]["message"]
    else
      assert :ok = GoogleRecords.call(c.path, c.import, context)
    end

    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
