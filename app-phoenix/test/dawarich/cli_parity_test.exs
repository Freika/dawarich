defmodule Dawarich.CLIParityTest do
  use Dawarich.JobsCase

  alias Dawarich.A12eCorpus

  @external_resource A12eCorpus.path()
  @ported ~w(users_activate users_activate_cloud users_admin_recipe users_email_recipe users_password_recipe jobs_status_absent jobs_status_full jobs_status_stale_alarm raw_data_archive raw_data_archive_full raw_data_archive_full_failed raw_data_archive_nothing raw_data_clear_all raw_data_clear_month raw_data_reset_all raw_data_reset_all_declined raw_data_reset_all_nothing raw_data_restore raw_data_restore_all raw_data_restore_all_unknown raw_data_restore_missing raw_data_restore_usage raw_data_status raw_data_status_empty raw_data_verify_all raw_data_verify_month)

  for c <- A12eCorpus.cases(), c["name"] in @ported do
    @case c
    test "#{c["name"]} prints, returns and stores what Rails did" do
      result = A12eCorpus.replay(@case)
      if @case["stdout"], do: assert(result.stdout == A12eCorpus.expected_stdout(@case))
      if @case["stderr"], do: assert(A12eCorpus.stderr_message(result.stderr) == @case["stderr"])
      assert result.exit == @case["exit"]
      assert result.checks == A12eCorpus.expected_checks(@case)
    end
  end

  test "every recorded case is replayed" do
    assert Enum.sort(@ported) == A12eCorpus.cases() |> Enum.map(& &1["name"]) |> Enum.sort()
  end
end
