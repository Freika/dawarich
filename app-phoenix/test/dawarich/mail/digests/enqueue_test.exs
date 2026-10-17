defmodule Dawarich.Mail.Digests.EnqueueTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures
  alias Dawarich.Mail.Digests.{Enqueue, MonthlyWorker, YearlyWorker}

  @path Path.expand("../../../fixtures/mail/residual/effects.json", __DIR__)
  @content Path.expand("../../../fixtures/mail/residual/digest_content.json", __DIR__)
  @now ~U[2026-10-04 12:00:00Z]
  @names ~w(default inactive toggle_off legacy_off legacy_on explicit_off missing_digest missing_user
            deleted_user zero negative enqueue_failure save_failure smtp_failure sent clear_sent
            blank_fr invalid_fr changed_preference generation_locale missing_after_enqueue deleted_after_enqueue)

  test "digest enqueue guards and sent at timing match Rails effects" do
    start_oban(:residual_enqueue)
    oban = :residual_enqueue
    cases = @path |> File.read!() |> Jason.decode!() |> Map.fetch!("digests")

    assert Enum.map(cases, & &1["id"]) ==
             for(name <- @names, period <- ~w(monthly yearly), do: "#{period}_#{name}")

    ordered =
      Enum.with_index(cases)
      |> Enum.sort_by(fn {row, _} -> not String.ends_with?(row["id"], "enqueue_failure") end)

    for {row, index} <- ordered do
      reset!(ScratchRepo)
      [id, year | month] = row["stage"]["arguments"]
      digest_id = 460_200 + index
      name = String.replace_prefix(row["id"], row["period"] <> "_", "")
      load(row, digest_id, name)
      worker = if row["period"] == "monthly", do: MonthlyWorker, else: YearlyWorker

      payload = %{
        "user_id" => id,
        "year" => year,
        "time_zone" => row["stage"]["timezone"],
        "locale" => row["stage"]["locale"]
      }

      payload = if month == [], do: payload, else: Map.put(payload, "month", hd(month))
      assert {:ok, ^payload} = worker.args_from_command(1, payload)

      assert worker.args_from_command(1, Map.delete(payload, "locale")) ==
               {:error, "invalid_payload"}

      assert worker.args_from_command(1, Map.put(payload, "extra", 1)) ==
               {:error, "invalid_payload"}

      assert worker.args_from_command(2, payload) == {:error, "unsupported_version"}
      args = Map.put(payload, "event_id", Ecto.UUID.generate())

      if name == "enqueue_failure" do
        rows(
          "ALTER TABLE oban.oban_jobs ADD CONSTRAINT a12c_enqueue_failure CHECK (worker <> 'Dawarich.Mail.Digests.DeliveryWorker')"
        )
      end

      observed = fn ->
        assert [[nil]] = rows("SELECT sent_at FROM public.digests WHERE id=$1", [digest_id])
      end

      result =
        Enqueue.run(ScratchRepo, row["period"], args,
          oban: oban,
          now: @now,
          after_enqueue: observed
        )

      if name == "enqueue_failure" do
        rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT a12c_enqueue_failure")
      end

      assert match?({:error, _}, result) == not is_nil(row["error"]), row["id"]
      assert [[count]] = rows("SELECT count(*) FROM oban.oban_jobs")
      assert count == length(row["mail_jobs"]), row["id"]
      expected = row["queued_sent_at"]
      actual = rows("SELECT sent_at FROM public.digests WHERE id=$1", [digest_id])

      actual =
        case actual do
          [] ->
            nil

          [[nil]] ->
            nil

          [[time]] ->
            (time |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()) <> "Z"
        end

      assert actual == expected, row["id"]

      if count == 1 do
        [[delivery]] = rows("SELECT args FROM oban.oban_jobs")
        assert delivery["locale"] == payload["locale"], row["id"]
        assert delivery["time_zone"] == payload["time_zone"]
        assert delivery["digest_id"] == digest_id
        assert delivery["event_id"] == args["event_id"]
        assert delivery["user_id"] == id
      end
    end
  end

  defp load(row, digest_id, name) do
    [id, year | month] = row["stage"]["arguments"]
    id = if name == "missing_user", do: 460_199, else: id

    user = %{
      "id" => id,
      "email" => row["recipient"],
      "settings" => row["settings"],
      "created_at" => @now,
      "updated_at" => @now,
      "status" => if(name == "inactive", do: 1, else: 0)
    }

    user = if name == "deleted_user", do: Map.put(user, "deleted_at", @now), else: user
    DigestFixtures.row!(ScratchRepo, "users", user)

    template =
      @content
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == row["period"] <> "_km"))

    digest =
      template["digest"]
      |> Map.merge(%{
        "id" => digest_id,
        "user_id" => id,
        "year" => year,
        "month" => List.first(month),
        "period_type" => if(row["period"] == "monthly", do: 0, else: 1),
        "created_at" => @now,
        "updated_at" => @now
      })

    digest = if name == "save_failure", do: Map.put(digest, "month", 13), else: digest
    digest = if name == "zero", do: Map.put(digest, "distance", 0), else: digest
    digest = if name == "negative", do: Map.put(digest, "distance", -1500), else: digest

    digest =
      if name == "sent", do: Map.put(digest, "sent_at", "2026-10-03T12:00:00Z"), else: digest

    unless name == "missing_digest", do: DigestFixtures.row!(ScratchRepo, "digests", digest)
  end
end
