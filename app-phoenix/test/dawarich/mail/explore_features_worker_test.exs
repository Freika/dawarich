defmodule Dawarich.Mail.ExploreFeaturesWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  use Oban.Testing, repo: Dawarich.ScratchRepo
  alias Dawarich.Mail.ExploreFeaturesWorker

  defp user!(attrs \\ %{}) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, deleted_at, created_at, updated_at) VALUES ($1, $2, $3, now(), now()) RETURNING id",
        [
          Map.get(attrs, :email, "m@example.test"),
          Map.get(attrs, :settings, %{"locale" => "de"}),
          Map.get(attrs, :deleted_at)
        ]
      )

    id
  end

  defp args(user_id, event_id \\ Ecto.UUID.generate()),
    do: %{"event_id" => event_id, "user_id" => user_id, "locale" => "en"}

  defp marked?(event_id),
    do:
      rows("SELECT count(*) FROM phoenix.processed_commands WHERE event_id = $1", [
        Ecto.UUID.dump!(event_id)
      ]) == [[1]]

  test "sends once in the user's locale and records the sent marker" do
    event_id = Ecto.UUID.generate()
    assert perform_job(ExploreFeaturesWorker, args(user!(), event_id)) == :ok
    assert_received {:mail, %{to: "m@example.test", subject: subject}}
    refute_received {:mail, _}
    assert {:ok, ^subject} = Dawarich.I18n.t("de", "mailers.users.explore_features.subject")
    assert marked?(event_id)
  end

  test "a marked event sends nothing" do
    event_id = Ecto.UUID.generate()
    :ok = Dawarich.Jobs.Processed.mark!(ScratchRepo, event_id, "users.explore_features_mail")
    assert perform_job(ExploreFeaturesWorker, args(user!(), event_id)) == :ok
    refute_received {:mail, _}
  end

  test "has a five-minute execution timeout, well below Lifeline's rescue window" do
    assert ExploreFeaturesWorker.timeout(%Oban.Job{}) == :timer.minutes(5)
  end

  test "a missing or soft-deleted user is a silent no-op, like find_user_or_skip" do
    deleted = user!(%{email: "gone@example.test", deleted_at: DateTime.utc_now()})
    assert perform_job(ExploreFeaturesWorker, args(deleted)) == :ok
    assert perform_job(ExploreFeaturesWorker, args(deleted + 1_000)) == :ok
    refute_received {:mail, _}
  end

  test "an SMTP error fails the attempt and leaves no marker" do
    event_id = Ecto.UUID.generate()
    Process.put(:transport_result, {:error, {:temporary_failure, "451"}})

    assert perform_job(ExploreFeaturesWorker, args(user!(), event_id)) ==
             {:error, {:temporary_failure, "451"}}

    refute marked?(event_id)
  end

  test "a crash between acceptance and the marker sends twice: Rails' at-least-once window, kept (D3)" do
    user_id = user!()
    event_id = Ecto.UUID.generate()
    Process.put(:crash_after_send, true)

    assert_raise RuntimeError, fn ->
      perform_job(ExploreFeaturesWorker, args(user_id, event_id))
    end

    Process.delete(:crash_after_send)
    assert perform_job(ExploreFeaturesWorker, args(user_id, event_id)) == :ok
    assert_received {:mail, _}
    assert_received {:mail, _}
    assert marked?(event_id)
  end

  test "a job orphaned in executing is rescued by lifeline once and still sends once" do
    name = Dawarich.LifelineTestOban

    start_oban(name,
      testing: :disabled,
      queues: [],
      stager: false,
      peer: {Oban.Peers.Isolated, leader?: true},
      plugins: [],
      lifeline: [rescue_after: {60, :minute}]
    )

    event_id = Ecto.UUID.generate()
    {:ok, job} = Oban.insert(name, ExploreFeaturesWorker.new(args(user!(), event_id)))

    rows(
      "UPDATE oban.oban_jobs SET state = 'executing', attempt = 1, attempted_at = now() - interval '2 hours' WHERE id = $1",
      [job.id]
    )

    lifeline = Oban.Registry.whereis(name, {:plugin, Oban.Lifeline})
    send(lifeline, :rescue)
    :sys.get_state(lifeline)

    assert rows("SELECT state FROM oban.oban_jobs WHERE id = $1", [job.id]) == [["available"]]
    assert %{success: 1} = Oban.drain_queue(name, queue: :mailers)
    assert_received {:mail, _}
    refute_received {:mail, _}
    assert marked?(event_id)
  end

  test "decodes version 1 commands only" do
    assert ExploreFeaturesWorker.args_from_command(1, %{"user_id" => 5, "locale" => "de"}) ==
             {:ok, %{"user_id" => 5, "locale" => "de"}}

    assert ExploreFeaturesWorker.args_from_command(1, %{"user_id" => "5"}) ==
             {:error, "invalid_payload"}

    assert ExploreFeaturesWorker.args_from_command(1, %{
             "user_id" => 5,
             "locale" => "de",
             "unexpected" => true
           }) == {:error, "invalid_payload"}

    assert ExploreFeaturesWorker.args_from_command(2, %{"user_id" => 5}) ==
             {:error, "unsupported_version"}
  end
end
