defmodule Dawarich.A12f3bM12Test do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.Drain
  alias Dawarich.Mail.{WelcomeWorker, Wave2}

  @tag a12f3b_case: "M12a"
  test "dormant mail APIs never fabricate successful delivery or erase queued debt" do
    source = %{
      "status" => "BLOCKED",
      "observation" => true,
      "counts" => %{
        "queued" => 1,
        "scheduled" => 0,
        "retry" => 0,
        "dead" => 0,
        "busy" => 0,
        "unknown" => 1
      },
      "classes" => %{"unknown" => 1},
      "reasons" => ["queued_work", "unknown_work"]
    }

    status = Drain.status(ScratchRepo, source_status: source)
    assert status.forward == "BLOCKED"
    assert status.binary_rollback == "BLOCKED"
    assert "source_wrapper_debt" in status.forward_reasons
    assert "source_wrapper_debt" in status.binary_reasons
    assert status.source_status == source
    refute_received {:mail, _}
    assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]
    invalid = Drain.status(ScratchRepo, source_status: %{"status" => "OBSERVED_EMPTY"})
    assert "source_census_unreadable" in invalid.binary_reasons
  end

  @tag a12f3b_case: "M12b"
  test "missing recipient wrapper remains source discard with no guessed native decode" do
    for kind <-
          ~w(confirmation_instructions member_joined trial_expired trial_expires_soon post_trial_reminder_early post_trial_reminder_late),
        wrapper <- ["gid://dawarich/User/12345", %{"_aj_globalid" => "gid://dawarich/User/12345"}] do
      assert WelcomeWorker.args_from_command(1, %{"user_id" => wrapper, "locale" => "en"}) ==
               {:error, "invalid_payload"},
             kind

      assert Wave2.decode(1, %{"user_id" => wrapper}, %{"user_id" => :integer}) ==
               {:error, "invalid_payload"},
             kind
    end

    assert WelcomeWorker.perform(%Oban.Job{
             args: %{"user_id" => -12345, "locale" => "en", "event_id" => Ecto.UUID.generate()}
           }) == :ok

    refute_received {:mail, _}
    assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]
  end
end
