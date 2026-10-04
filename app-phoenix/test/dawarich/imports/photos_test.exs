defmodule Dawarich.Imports.PhotosTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{GooglePhotos, Photos, JsonStream}
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  setup do
    Dawarich.Ingest.Sources.forget()
    :ok
  end

  test "google photos fallback fields and milliseconds match Rails" do
    for path <- Path.wildcard(Path.join(@dir, "google_photos_import_*.json")),
        not String.ends_with?(path, ".input.json") do
      check(Path.basename(path, ".json"), GooglePhotos)
    end
  end

  test "generated photos preserve supplied WKT and source semantics" do
    for path <- Path.wildcard(Path.join(@dir, "photos_*.json")),
        not String.ends_with?(path, ".input.json") do
      check(Path.basename(path, ".json"), Photos)
    end
  end

  defp check(name, adapter) do
    c = NormalFormats.seed!(name, ScratchRepo)

    if c.expected["legacy"] do
      assert {:error, :legacy_checked} =
               ScratchRepo.transaction(fn ->
                 ScratchRepo.query!(
                   "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                 )

                 Dawarich.Ingest.Sources.forget()
                 run(c, adapter, %{c.context | altitude_decimal?: false})
                 ScratchRepo.rollback(:legacy_checked)
               end)

      Dawarich.Ingest.Sources.forget()
    else
      run(c, adapter, %{c.context | now: fn -> c.context.now end})
    end
  end

  defp run(c, adapter, context) do
    if c.expected["error"] do
      if c.expected["error"]["class"] == "JSON::ParserError" do
        assert_raise JsonStream.Error, fn -> adapter.call(c.path, c.import, context) end
      else
        error = assert_raise ArgumentError, fn -> adapter.call(c.path, c.import, context) end
        assert Exception.message(error) == c.expected["error"]["message"]
      end
    else
      repeats =
        if adapter == GooglePhotos &&
             String.ends_with?(c.expected["input"], "_duplicate.input.json"),
           do: 2,
           else: 1

      for _ <- 1..repeats, do: assert(:ok = adapter.call(c.path, c.import, context))
    end

    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
