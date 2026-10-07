defmodule Dawarich.A12f3bM05Test do
  use Dawarich.JobsCase
  alias Dawarich.Mail.ArchivalApproachingWorker
  alias Dawarich.Lite.ArchivalWarningWorker
  alias Dawarich.Jobs.Ownership
  @now ~U[2026-03-29 01:30:00Z]

  setup do
    names = ~w(SELF_HOSTED MANAGER_URL JWT_SECRET_KEY)
    previous = Map.take(System.get_env(), names)

    System.put_env(%{
      "SELF_HOSTED" => "false",
      "MANAGER_URL" => "https://manager.example.test",
      "JWT_SECRET_KEY" => "synthetic-archival-key"
    })

    on_exit(fn ->
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
    end)

    start_oban(:mail_archival)
    Ownership.put!(ScratchRepo, ArchivalWarningWorker.key(), :oban)
    :ok
  end

  defp user! do
    [[id]] =
      rows(
        "INSERT INTO users(email,plan,settings,created_at,updated_at) VALUES('archival@example.test',0,'{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    rows(
      "INSERT INTO points(user_id,timestamp,created_at,updated_at) VALUES($1,1744594100,now(),now())",
      [id]
    )

    id
  end

  @tag a12f3b_case: "M05a"
  test "lite archival warning atomically schedules source mail and warning marker" do
    id = user!()
    assert ArchivalWarningWorker.run(ScratchRepo, :mail_archival, @now, "Europe/Berlin") == :ok

    assert rows("SELECT settings->'archival_warnings'->>'11_5mo' FROM users WHERE id=$1", [id]) ==
             [["2026-03-29T03:30:00+02:00"]]

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["user_id"] == id
    Process.put(:transport_result, {:error, :rejected})
    assert ArchivalApproachingWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, mail}
    assert mail.text =~ "utm_campaign=archival_approaching"
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
    assert ArchivalWarningWorker.run(ScratchRepo, :mail_archival, @now, "Europe/Berlin") == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end

  @tag a12f3b_case: "M05b"
  test "archival warning replay preserves the first provider identity" do
    args = %{
      "user_id" => user!(),
      "locale" => "fr",
      "epoch" => "accepted-warning",
      "event_id" => Ecto.UUID.generate()
    }

    Process.put(:transport_result, {:error, :rejected})
    assert ArchivalApproachingWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, first}
    Process.delete(:transport_result)
    assert ArchivalApproachingWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, second}
    assert first.message_id == second.message_id
    if first.text != second.text, do: flunk("subscription link changed on retry")
    if first.html != second.html, do: flunk("subscription HTML changed on retry")
    assert ArchivalApproachingWorker.perform(%Oban.Job{args: args}) == :ok
    refute_received {:mail, _}
  end
end
