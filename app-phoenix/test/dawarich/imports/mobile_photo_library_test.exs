defmodule Dawarich.Imports.MobilePhotoLibraryTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{JsonStream, MobilePhotoLibrary}
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  setup do
    Dawarich.Ingest.Sources.forget()
    :ok
  end

  test "mobile photo invalid version produces no effects" do
    for name <- ~w(version wrong_type wrong_points missing_points array null empty malformed) do
      c = NormalFormats.seed!("mobile_import_" <> name, ScratchRepo)

      exception =
        if c.expected["error"]["class"] == "ArgumentError",
          do: ArgumentError,
          else: JsonStream.Error

      error =
        assert_raise exception, fn -> MobilePhotoLibrary.call(c.path, c.import, c.context) end

      if exception == ArgumentError,
        do: assert(Exception.message(error) == c.expected["error"]["message"])

      NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
      assert c.expected["points"] == []
    end
  end

  test "mobile photo bounds and rejection progress match Rails" do
    for path <- Path.wildcard(Path.join(@dir, "mobile_import_*.json")),
        not String.ends_with?(path, ".input.json") do
      c = NormalFormats.seed!(Path.basename(path, ".json"), ScratchRepo)

      unless c.expected["error"] do
        if c.expected["legacy"] do
          assert {:error, :legacy_checked} =
                   ScratchRepo.transaction(fn ->
                     ScratchRepo.query!(
                       "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                     )

                     Dawarich.Ingest.Sources.forget()

                     assert :ok =
                              MobilePhotoLibrary.call(c.path, c.import, %{
                                c.context
                                | altitude_decimal?: false
                              })

                     NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
                     ScratchRepo.rollback(:legacy_checked)
                   end)

          Dawarich.Ingest.Sources.forget()
        else
          assert :ok =
                   MobilePhotoLibrary.call(c.path, c.import, %{
                     c.context
                     | now: fn -> c.context.now end
                   })

          NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
        end
      end
    end
  end
end
