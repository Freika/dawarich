defmodule Dawarich.Mail.ReviewFindingsTest do
  use Dawarich.JobsCase

  alias Dawarich.Mail.{
    ArchivalApproachingWorker,
    Delivery,
    DeviseCallbacks,
    DeviseNotificationWorker,
    TestEmail,
    TestEmailWorker
  }

  defmodule GatedTransport do
    def deliver(_message, _env) do
      send(Application.fetch_env!(:dawarich, :mail_review_observer), {:transport_entered, self()})
      receive do: (:release -> :ok)
    end
  end

  setup do
    names = ~w(SELF_HOSTED RAILS_ENV MANAGER_URL JWT_SECRET_KEY)
    previous = Map.take(System.get_env(), names)
    transport = Application.fetch_env!(:dawarich, :mail_transport)

    System.put_env(%{
      "SELF_HOSTED" => "true",
      "RAILS_ENV" => "production",
      "MANAGER_URL" => "https://manager.example.test",
      "JWT_SECRET_KEY" => "synthetic-mail-review"
    })

    on_exit(fn ->
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
      Application.put_env(:dawarich, :mail_transport, transport)
      Application.delete_env(:dawarich, :mail_review_observer)
    end)

    :ok
  end

  defp user!(admin \\ true) do
    [[id]] =
      rows(
        "INSERT INTO users(email,encrypted_password,admin,settings,created_at,updated_at) VALUES('review@example.test','old-hash',$1,'{}',now(),now()) RETURNING id",
        [admin]
      )

    id
  end

  defp gate do
    Application.put_env(:dawarich, :mail_transport, GatedTransport)
    Application.put_env(:dawarich, :mail_review_observer, self())
  end

  @tag mail_review: "F1"
  test "credential inline and queued execution share one durable delivery owner" do
    start_oban(:review_credentials)
    id = user!()
    gate()

    inline =
      Task.async(fn ->
        DeviseCallbacks.update(ScratchRepo, id, %{email: "changed@example.test"},
          env: %{"SELF_HOSTED" => "false", "RAILS_ENV" => "production"},
          oban: :review_credentials
        )
      end)

    assert_receive {:transport_entered, inline_pid}, 5000

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Mail.DeviseNotificationWorker'"
      )

    assert rows("SELECT email FROM users WHERE id=$1", [id]) == [["changed@example.test"]]

    queued =
      Task.async(fn ->
        result = DeviseNotificationWorker.perform(%Oban.Job{args: args})
        result
      end)

    outcome =
      receive do
        {:transport_entered, queue_pid} ->
          send(queue_pid, :release)
          :duplicate

        {ref, result} when ref == queued.ref ->
          Process.demonitor(ref, [:flush])
          result
      after
        5000 -> :stuck
      end

    send(inline_pid, :release)
    assert {:ok, _} = Task.await(inline, 5000)
    if outcome == :duplicate, do: Task.await(queued, 5000)
    if outcome == :stuck, do: Task.shutdown(queued)
    assert outcome == {:snooze, 600}
    assert DeviseNotificationWorker.perform(%Oban.Job{args: args}) == :ok
    refute_received {:transport_entered, _}

    assert rows("SELECT count(*) FROM phoenix.delivery_claims WHERE delivered_at IS NOT NULL") ==
             [[1]]
  end

  @tag mail_review: "F3"
  test "an old retry refreshes its attempt deadline and a live delivery cannot be taken over" do
    now = DateTime.utc_now()
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()
    handler = "mail.review.lease"
    key = "retry"
    assert Delivery.claim(ScratchRepo, handler, key, first, DateTime.add(now, -601)) == :send
    assert Delivery.claim(ScratchRepo, handler, key, first, now) == :send
    assert Delivery.claim(ScratchRepo, handler, key, second, now) == :held
    gate()

    active =
      Task.async(fn ->
        Delivery.deliver(ScratchRepo, handler, key, "record", first, fn -> {:ok, %{}} end)
      end)

    assert_receive {:transport_entered, pid}, 5000

    rows("UPDATE phoenix.delivery_claims SET claimed_at=$1 WHERE handler=$2", [
      DateTime.add(now, -601),
      handler
    ])

    assert Delivery.deliver(ScratchRepo, handler, key, "record", second, fn -> {:ok, %{}} end) ==
             {:snooze, 600}

    assert Delivery.claim(ScratchRepo, handler, key, second, now) == :held
    send(pid, :release)
    assert Task.await(active, 5000) == :ok
    assert Delivery.delivered!(ScratchRepo, handler, key, second) == {:error, :claim_lost}
    refute_received {:transport_entered, _}
  end

  @tag mail_review: "F4"
  test "successful test email redelivery sends once while separate accepted jobs remain distinct" do
    id = user!()
    args = %{"user_id" => id, "locale" => "en"}
    job = %Oban.Job{id: 123, args: args}
    assert TestEmailWorker.perform(job) == :ok
    assert_received {:mail, _}
    assert TestEmailWorker.perform(job) == :ok
    refute_received {:mail, _}

    assert rows("SELECT count(*) FROM phoenix.delivery_claims WHERE delivered_at IS NOT NULL") ==
             [[1]]

    assert TestEmailWorker.perform(%Oban.Job{id: 124, args: args}) == :ok
    assert_received {:mail, _}
    start_oban(:review_test_email)
    user = %{id: id, email: "review@example.test", settings: %{}, admin: true}

    for _ <- 1..2,
        do:
          assert(
            {:notice, _} =
              TestEmail.run(user, "en", %{"SMTP_SERVER" => "synthetic.test"},
                oban: :review_test_email
              )
          )

    [[a], [b]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id")
    assert is_binary(a["event_id"])
    refute a["event_id"] == b["event_id"]
  end

  @tag mail_review: "F5Worker"
  test "test email producer and worker refuse non admins including demotion after enqueue" do
    start_oban(:review_authorization)
    id = user!(false)
    user = %{id: id, email: "review@example.test", settings: %{}, admin: false}

    assert {:alert, _} =
             TestEmail.run(user, "en", %{"SMTP_SERVER" => "synthetic.test"},
               oban: :review_authorization
             )

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]

    assert TestEmailWorker.perform(%Oban.Job{id: 123, args: %{"user_id" => id, "locale" => "en"}}) ==
             {:cancel, "admin required"}

    refute_received {:mail, _}
    rows("UPDATE users SET admin=true WHERE id=$1", [id])

    assert {:notice, _} =
             TestEmail.run(%{user | admin: true}, "en", %{"SMTP_SERVER" => "synthetic.test"},
               oban: :review_authorization
             )

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    rows("UPDATE users SET admin=false WHERE id=$1", [id])
    assert TestEmailWorker.perform(%Oban.Job{args: args}) == {:cancel, "admin required"}
    refute_received {:mail, _}
    assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]
  end

  @tag mail_review: "F6"
  test "late archival retries cancel instead of delivering an expired accepted upgrade link" do
    id = user!()
    System.put_env("SELF_HOSTED", "false")

    args = %{
      "user_id" => id,
      "locale" => "en",
      "epoch" => "accepted-warning",
      "event_id" => Ecto.UUID.generate()
    }

    handler = "mail.user.archival_approaching"
    key = ArchivalApproachingWorker.provider_key(args)

    assert Delivery.claim(
             ScratchRepo,
             handler,
             key,
             args["event_id"],
             DateTime.add(DateTime.utc_now(), -1802)
           ) == :send

    assert ArchivalApproachingWorker.perform(%Oban.Job{args: args}) ==
             {:cancel, "archival upgrade link expired"}

    refute_received {:mail, _}
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
  end
end
