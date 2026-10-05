defmodule Dawarich.Mail.Digests.DeliveryWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures
  alias Dawarich.Mail.Delivery
  alias Dawarich.Mail.Digests.{DeliveryWorker, Enqueue, MonthlyWorker, YearlyWorker}

  @effects Path.expand("../../../fixtures/mail/residual/effects.json", __DIR__)
  @content Path.expand("../../../fixtures/mail/residual/digest_content.json", __DIR__)
  @now ~U[2026-10-04 12:00:00Z]

  setup do
    previous = Map.take(System.get_env(), ~w(SMTP_FROM DOMAIN RAILS_ENV))

    System.put_env(%{
      "SMTP_FROM" => "Dawarich <residual@dawarich.test>",
      "DOMAIN" => "www.example.com",
      "RAILS_ENV" => "staging"
    })

    on_exit(fn ->
      Enum.each(~w(SMTP_FROM DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    start_oban(:residual_delivery)
    :ok
  end

  test "queued digest delivery survives sent at and transport failure without changing staging state" do
    cases =
      effects()
      |> Enum.filter(fn {row, _} ->
        String.ends_with?(row["id"], [
          "smtp_failure",
          "missing_after_enqueue",
          "deleted_after_enqueue"
        ])
      end)

    assert length(cases) == 6

    for {row, index} <- cases do
      reset!(ScratchRepo)
      args = stage(row, index)
      id = args["digest_id"]
      timestamp = rows("SELECT sent_at, updated_at FROM public.digests WHERE id=$1", [id])
      assert [[sent, _]] = timestamp
      refute is_nil(sent)

      cond do
        String.ends_with?(row["id"], "missing_after_enqueue") ->
          rows("DELETE FROM public.digests WHERE id=$1", [id])

        String.ends_with?(row["id"], "deleted_after_enqueue") ->
          rows("UPDATE public.users SET deleted_at=$2 WHERE id=$1", [
            args["user_id"],
            DateTime.to_naive(@now)
          ])

        true ->
          Process.put(:transport_result, {:error, "synthetic SMTP failure"})
      end

      result = DeliveryWorker.perform(%Oban.Job{args: args})
      failed = String.ends_with?(row["id"], "smtp_failure")
      assert match?({:error, _}, result) == failed, row["id"]
      sent_count = if row["smtp"]["attempts"] == [], do: 0, else: 1
      if sent_count == 1, do: assert_received({:mail, _}), else: refute_received({:mail, _})
      expected = if sent_count == 0, do: [], else: timestamp
      assert rows("SELECT sent_at, updated_at FROM public.digests WHERE id=$1", [id]) == expected
      Process.delete(:transport_result)

      if failed do
        key = DeliveryWorker.provider_key(args)
        contender = Map.put(args, "event_id", Ecto.UUID.generate())
        assert Delivery.claim(ScratchRepo, "mail.digest", key, contender["event_id"]) == :held
        assert DeliveryWorker.perform(%Oban.Job{args: args}) == :ok
        assert_received {:mail, %{message_id: message_id}}
        assert DeliveryWorker.perform(%Oban.Job{args: args}) == :ok
        refute_received {:mail, _}

        assert rows("SELECT sent_at, updated_at FROM public.digests WHERE id=$1", [id]) ==
                 timestamp

        rows("UPDATE public.digests SET sent_at=NULL WHERE id=$1", [id])

        next_args =
          args
          |> Map.delete("digest_id")
          |> Map.merge(%{"year" => 2024, "event_id" => Ecto.UUID.generate()})

        next_args =
          if row["period"] == "monthly", do: Map.put(next_args, "month", 2), else: next_args

        assert Enqueue.run(ScratchRepo, row["period"], next_args,
                 oban: :residual_delivery,
                 now: @now
               ) == :ok

        [[new_args]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
        assert DeliveryWorker.perform(%Oban.Job{args: new_args}) == :ok
        assert_received {:mail, %{message_id: next_id}}
        refute next_id == message_id
      end
    end
  end

  test "digest ambient locale survives both queues and preference changes before SMTP" do
    cases =
      effects()
      |> Enum.filter(fn {row, _} ->
        String.ends_with?(row["id"], [
          "blank_fr",
          "invalid_fr",
          "changed_preference",
          "generation_locale"
        ])
      end)

    assert length(cases) == 8

    for {row, index} <- cases do
      reset!(ScratchRepo)
      args = stage(row, index)
      assert args["locale"] == row["stage"]["locale"]
      settings = Map.put(row["settings"], "locale", row["final_preference"])
      rows("UPDATE public.users SET settings=$2 WHERE id=$1", [args["user_id"], settings])
      assert DeliveryWorker.perform(%Oban.Job{args: args}) == :ok
      assert_received {:mail, message}
      expected = hd(row["smtp"]["attempts"])
      assert message.subject == expected["subject"], "subject differs: #{row["id"]}"
      assert message.to == hd(expected["to"]), "recipient differs: #{row["id"]}"
      assert message.locale == (row["final_preference"] || args["locale"])

      if message.text != hd(expected["tree"]["parts"])["body"],
        do: flunk("text differs: #{row["id"]}")

      if message.html != List.last(expected["tree"]["parts"])["body"],
        do: flunk("HTML differs: #{row["id"]}")

      refute_received {:mail, _}
    end
  end

  test "foreign user digest pairs create no SMTP attempt or delivery claim" do
    for {row, index} <- effects(), String.ends_with?(row["id"], "smtp_failure") do
      reset!(ScratchRepo)
      args = stage(row, index)

      DigestFixtures.row!(ScratchRepo, "users", %{
        "id" => 460_999,
        "email" => "foreign-digest@test",
        "settings" => %{"locale" => "en"},
        "created_at" => @now,
        "updated_at" => @now
      })

      args = Map.put(args, "user_id", 460_999)
      assert DeliveryWorker.perform(%Oban.Job{args: args}) == :ok

      receive do
        {:mail, _} -> flunk("foreign digest reached SMTP")
      after
        0 -> :ok
      end

      assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]
    end
  end

  defp effects,
    do: @effects |> File.read!() |> Jason.decode!() |> Map.fetch!("digests") |> Enum.with_index()

  defp stage(row, index) do
    [id, year | month] = row["stage"]["arguments"]

    DigestFixtures.row!(ScratchRepo, "users", %{
      "id" => id,
      "email" => row["recipient"],
      "settings" => row["settings"],
      "created_at" => @now,
      "updated_at" => @now
    })

    template =
      @content
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == row["period"] <> "_km"))

    digest =
      template["digest"]
      |> Map.merge(%{
        "id" => 460_200 + index,
        "user_id" => id,
        "period_type" => if(row["period"] == "monthly", do: 0, else: 1),
        "created_at" => @now,
        "updated_at" => @now,
        "sharing_uuid" =>
          "46000000-0000-4000-8000-" <> String.pad_leading(to_string(index), 12, "0")
      })

    DigestFixtures.row!(ScratchRepo, "digests", digest)
    worker = if row["period"] == "monthly", do: MonthlyWorker, else: YearlyWorker

    payload = %{
      "user_id" => id,
      "year" => year,
      "locale" => row["stage"]["locale"],
      "time_zone" => row["stage"]["timezone"]
    }

    payload = if month == [], do: payload, else: Map.put(payload, "month", hd(month))
    assert {:ok, ^payload} = worker.args_from_command(1, payload)

    assert Enqueue.run(
             ScratchRepo,
             row["period"],
             Map.put(payload, "event_id", Ecto.UUID.generate()),
             oban: :residual_delivery,
             now: @now
           ) == :ok

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    args
  end
end
