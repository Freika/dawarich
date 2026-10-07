defmodule Dawarich.A12f3bM11Test do
  use Dawarich.JobsCase
  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail.Digests.{DeliveryWorker, Enqueue}
  alias Dawarich.Mail.ResidualCommands
  @now ~U[2026-10-04 12:00:00.000000Z]
  @content Path.expand("../fixtures/mail/residual/digest_content.json", __DIR__)

  setup do
    start_oban(:mail_digest_cases)
    previous = Map.take(System.get_env(), ~w(DOMAIN RAILS_ENV))
    System.put_env(%{"DOMAIN" => "digest.example.test", "RAILS_ENV" => "production"})

    on_exit(fn ->
      Enum.each(~w(DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    :ok
  end

  defp data!(period) do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('digest@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    template =
      @content
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == period <> "_km"))

    digest =
      Map.merge(template["digest"], %{
        "id" => id + 100_000,
        "user_id" => id,
        "created_at" => @now,
        "updated_at" => @now,
        "period_type" => if(period == "monthly", do: 0, else: 1)
      })

    F.row!(ScratchRepo, "digests", digest)

    args = %{
      "user_id" => id,
      "year" => 2024,
      "locale" => "fr",
      "time_zone" => "Europe/Berlin",
      "event_id" => Ecto.UUID.generate()
    }

    args = if period == "monthly", do: Map.put(args, "month", 2), else: args
    {digest["id"], args}
  end

  @tag a12f3b_case: "M11a"
  test "monthly and year-end digest callbacks preserve locale period and sent-at" do
    for period <- ["monthly", "yearly"] do
      reset!(ScratchRepo)
      {digest, args} = data!(period)

      assert Enqueue.run(ScratchRepo, period, args,
               oban: :mail_digest_cases,
               now: @now,
               after_enqueue: fn ->
                 assert rows("SELECT sent_at FROM digests WHERE id=$1", [digest]) == [[nil]]
               end
             ) == :ok

      assert rows("SELECT sent_at FROM digests WHERE id=$1", [digest]) == [
               [DateTime.to_naive(@now)]
             ]

      [[delivery]] = rows("SELECT args FROM oban.oban_jobs")
      Process.put(:transport_result, {:error, :rejected})
      assert {:error, _} = DeliveryWorker.perform(%Oban.Job{args: delivery})
      assert_received {:mail, mail}
      assert mail.to == "digest@example.test"
      assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]

      assert rows("SELECT sent_at FROM digests WHERE id=$1", [digest]) == [
               [DateTime.to_naive(@now)]
             ]

      Process.delete(:transport_result)
      rows("UPDATE digests SET sent_at=NULL WHERE id=$1", [digest])

      rows(
        "ALTER TABLE oban.oban_jobs ADD CONSTRAINT mail_digest_enqueue_failure CHECK(worker<>'Dawarich.Mail.Digests.DeliveryWorker') NOT VALID"
      )

      assert {:error, _} =
               Enqueue.run(ScratchRepo, period, args, oban: :mail_digest_cases, now: @now)

      rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT mail_digest_enqueue_failure")
      assert rows("SELECT sent_at FROM digests WHERE id=$1", [digest]) == [[nil]]
    end
  end

  @tag a12f3b_case: "M11b"
  test "digest mail retries retain period and first delivery identity" do
    for period <- ["monthly", "yearly"] do
      reset!(ScratchRepo)
      {_, args} = data!(period)
      Ownership.put!(ScratchRepo, "command:mail.digest." <> period, :oban)
      assert ResidualCommands.digest(ScratchRepo, period, args) == :ok
      first = rows("SELECT event_id,payload,scheduled_at FROM public.job_outbox")
      [[event, payload, _]] = first
      assert Ecto.UUID.cast!(event) != args["event_id"]
      assert payload["time_zone"] == "Europe/Berlin"
      rows("UPDATE public.job_outbox SET state='dispatched'")
      rows("UPDATE users SET settings='{\"locale\":\"en\"}' WHERE id=$1", [args["user_id"]])

      assert ResidualCommands.digest(ScratchRepo, period, Map.put(args, "time_zone", "UTC")) ==
               :ok

      assert rows("SELECT event_id,payload,scheduled_at FROM public.job_outbox") == first
    end
  end
end
