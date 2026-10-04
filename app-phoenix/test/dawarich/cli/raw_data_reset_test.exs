defmodule Dawarich.CLI.RawDataResetTest do
  use Dawarich.JobsCase

  alias Dawarich.A12eCorpus

  test "a point cleared by the cron during reset-all stays linked and its archive is kept" do
    c = A12eCorpus.case!("raw_data_reset_all")
    clear = fn -> rows("UPDATE points SET raw_data = '{}'::jsonb WHERE id = 26020") end
    result = A12eCorpus.replay(c, %{before_unflag: clear})

    assert result.exit == 1
    assert result.stderr =~ "still hold points whose raw_data was cleared"

    assert rows(
             "SELECT raw_data_archived, a.month FROM points p JOIN points_raw_data_archives a ON a.id = p.raw_data_archive_id WHERE p.id = 26020"
           ) ==
             [[true, 2]]

    assert rows(
             "SELECT count(*) FROM points WHERE raw_data_archived = false AND raw_data <> '{}'::jsonb"
           ) ==
             [[3]]
  end
end
