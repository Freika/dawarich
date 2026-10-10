defmodule Dawarich.Imports.FitTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Fit
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}

  test "fit hierarchy and Garmin flat records produce exactly one copy" do
    for name <-
          ~w(standard flat real_flat real_laps legacy multiple_sessions laps_fallback no_position duplicate skipped batch999 batch1000 batch1001 batch2001),
        do: run(name)
  end

  test "fit enhanced speed and parsing failure preserve Rails status" do
    for name <-
          ~w(enhanced missing_timestamp earlier_timestamp no_device empty no_type no_activity_timestamp absent_timestamp speed_zero speed_fallback),
        do: run(name)
  end

  test "fit CRC validation precedes point insertion" do
    for name <- ~w(bad_later_segment header_crc truncated data_crc), do: run(name)
  end

  defp run(name) do
    Dawarich.JobsCase.reset!(ScratchRepo)
    Dawarich.Ingest.Sources.forget()
    c = NormalFormats.seed!("fit_import_" <> name, ScratchRepo)
    c = %{c | context: %{c.context | altitude_decimal?: c.expected["legacy"] != true}}

    if c.expected["legacy"] do
      assert {:error, :legacy_checked} =
               ScratchRepo.transaction(fn ->
                 ScratchRepo.query!(
                   "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                 )

                 Dawarich.Ingest.Sources.forget()
                 check(c)
                 ScratchRepo.rollback(:legacy_checked)
               end)
    else
      check(c)
    end
  end

  defp check(c) do
    assert :ok = Fit.call(c.path, c.import, c.context)
    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
