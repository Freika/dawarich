defmodule Dawarich.Imports.GooglePhoneTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{GooglePhone, JsonStream}
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "phone late parser or second-batch failure rolls back all effects" do
    for path <- Path.wildcard(Path.join(@dir, "phone_import_*.json")),
        not String.ends_with?(path, ".input.json"),
        not String.contains?(path, "profile"),
        not String.ends_with?(path, "tie.json") do
      check(Path.basename(path, ".json"))
    end
  end

  test "phone profile and collision offsets use the first semantic start" do
    for path <- Path.wildcard(Path.join(@dir, "phone_import_profile*.json")),
        not String.ends_with?(path, ".input.json") do
      check(Path.basename(path, ".json"))
    end
  end

  test "phone tie offsets stop at Rails maximum 59" do
    check("phone_import_tie")
  end

  defp check(name) do
    Dawarich.JobsCase.reset!(ScratchRepo)
    Dawarich.Ingest.Sources.forget()
    c = NormalFormats.seed!(name, ScratchRepo)

    context = %{
      c.context
      | now: fn -> c.context.now end,
        altitude_decimal?: not (c.expected["legacy"] == true)
    }

    run = fn ->
      if c.expected["error"] do
        exception =
          case c.expected["error"]["class"] do
            "JSON::ParserError" -> JsonStream.Error
            "Oj::ParseError" -> JsonStream.Error
            "ActiveRecord::StatementInvalid" -> Postgrex.Error
            _ -> ArgumentError
          end

        error = assert_raise exception, fn -> GooglePhone.call(c.path, c.import, context) end

        if exception == Postgrex.Error,
          do:
            assert(
              Dawarich.Imports.NormalBatchErrors.message(error) == c.expected["error"]["message"]
            )
      else
        assert :ok = GooglePhone.call(c.path, c.import, context)
      end

      NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
    end

    if c.expected["legacy"] do
      assert {:error, :legacy_checked} =
               ScratchRepo.transaction(fn ->
                 ScratchRepo.query!(
                   "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                 )

                 Dawarich.Ingest.Sources.forget()
                 run.()
                 ScratchRepo.rollback(:legacy_checked)
               end)

      Dawarich.Ingest.Sources.forget()
    else
      if name == "phone_import_failure" do
        ScratchRepo.query!(
          "ALTER TABLE points ADD CONSTRAINT phone_batch_failure CHECK (CASE WHEN timestamp>=1768520800 THEN 1/(timestamp-timestamp) ELSE 1 END=1) NOT VALID"
        )

        try do
          run.()
        after
          ScratchRepo.query!("ALTER TABLE points DROP CONSTRAINT phone_batch_failure")
        end
      else
        run.()
      end
    end
  end
end
