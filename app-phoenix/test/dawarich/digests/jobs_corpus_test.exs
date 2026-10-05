defmodule Dawarich.Digests.JobsCorpusTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: F

  alias Dawarich.Digests.{
    Calculation,
    MonthlyScheduleWorker,
    MonthlyWorker,
    YearlyScheduleWorker,
    YearlyWorker
  }

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.Stats.{Accounts, CalculateMonth}

  @corpus __DIR__
          |> Path.join("../../fixtures/a12d1b2/jobs.json")
          |> File.read!()
          |> Jason.decode!()
  true = Enum.any?(@corpus["workers"], &(&1["profile"] == "year_boundary"))

  for row <- @corpus["schedulers"] do
    @row row
    test "native digest scheduler matches Rails b2 corpus: #{row["id"]}" do
      row = @row
      start_oban(__MODULE__)
      F.load_scheduler!(ScratchRepo, row)
      kind = row["kind"]
      worker = if kind == "monthly", do: MonthlyScheduleWorker, else: YearlyScheduleWorker
      type = if kind == "monthly", do: "digests.calculate_month", else: "digests.calculate_year"
      Ownership.put!(ScratchRepo, "cron:#{kind}_digest_scheduling_job", :oban)
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq)
      {:ok, now, 0} = DateTime.from_iso8601(row["now"])

      assert worker.perform(%Oban.Job{conf: %Oban.Config{name: __MODULE__}},
               now: now,
               zone: row["ambient_zone"]
             ) == :ok

      commands = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
      assert length(commands) == length(row["jobs"]), row["id"]

      for {[command_type, payload], recorded} <- Enum.zip(commands, row["jobs"]) do
        assert command_type == type
        assert arguments(payload, kind) == recorded["arguments"]
        assert payload["time_zone"] == recorded["timezone"]

        assert recorded["job_class"] ==
                 "Users::Digests::#{String.capitalize(kind)}::CalculatingJob"

        assert is_number(payload["run_at"])
      end
    end
  end

  for row <- @corpus["workers"] do
    @row row
    test "native digest worker matches Rails b2 corpus: #{row["id"]}" do
      row = @row
      start_oban(__MODULE__)
      kase = Map.merge(%{"legacy_duplicates" => false, "null_segment_mode" => false}, row)
      F.load!(ScratchRepo, kase)
      args = F.job_args(kase)
      worker = if row["kind"] == "monthly", do: MonthlyWorker, else: YearlyWorker
      assert worker.perform(%Oban.Job{args: args}, options(kase, args)) == :ok
      assert Processed.done?(ScratchRepo, args["event_id"])
      expected = row["expected"]
      actual = F.digests(ScratchRepo, 14101) |> Enum.map(&Map.delete(&1, "id"))
      assert actual == Enum.map(expected["rows"], &Map.delete(&1, "id")), row["id"]
      calls = drain_calls([])
      assert calls == expected["calls"], row["id"]

      emails =
        rows(
          "SELECT kind,payload FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%' ORDER BY id"
        )

      assert length(emails) == length(expected["emails"]), row["id"]

      for {[type, payload], recorded} <- Enum.zip(emails, expected["emails"]) do
        assert type ==
                 if(row["kind"] == "monthly",
                   do: "digests.email_month",
                   else: "digests.email_year"
                 )

        assert arguments(payload, row["kind"]) == recorded["arguments"]
        assert payload["time_zone"] == recorded["timezone"]
        assert recorded["locale"] == row["locale"]

        assert recorded["job_class"] ==
                 "Users::Digests::#{String.capitalize(row["kind"])}::EmailSendingJob"
      end

      notifications =
        rows("SELECT kind,title,content FROM notifications WHERE user_id=14101 ORDER BY id")

      assert length(notifications) == length(expected["notifications"]), row["id"]

      for {[code, title, body], [kind, expected_title, expected_body]} <-
            Enum.zip(notifications, expected["notifications"]) do
        assert Dawarich.Notifications.kind_name(code) == kind
        assert title == expected_title
        assert message_prefix(body) == message_prefix(expected_body), row["id"]

        if row["profile"] in ~w(digest_raise digest_database) do
          assert body == expected_body
        else
          assert body =~ "Dawarich.Digests.Run" or body =~ "Dawarich.Stats.CalculateMonth"
        end
      end

      stats =
        rows(
          "SELECT row_to_json(s)::text FROM (SELECT user_id,year,month,distance,flight_distance,daily_distance,toponyms,h3_hex_ids,calculation_version FROM stats WHERE user_id=14101 ORDER BY year,month) s"
        )
        |> Enum.map(fn [json] -> Jason.decode!(json) end)

      assert stats == expected["stats"], row["id"]
    end
  end

  defp options(kase, args) do
    parent = self()
    profile = kase["profile"]

    fault =
      if profile =~ "database",
        do: %Postgrex.Error{message: "synthetic digest failure"},
        else: %RuntimeError{message: "synthetic digest failure"}

    record = fn repo, id, call ->
      locale =
        case Accounts.find(repo, id) do
          nil -> kase["locale"]
          user -> ExploreFeatures.locale(user.settings, nil)
        end

      send(parent, {:call, Map.merge(call, %{"locale" => locale, "zone" => args["time_zone"]})})
    end

    stats = fn repo, id, year, month, opts ->
      unless profile == "vanished", do: record.(repo, id, %{"kind" => "stats", "month" => month})

      cond do
        profile == "vanished" ->
          repo.query!("UPDATE users SET deleted_at=$2 WHERE id=$1", [id, ~N[2026-10-03 12:00:00]],
            log: false
          )

          raise fault

        profile == "stats_raise" or (profile == "late_stats_raise" and month == 7) ->
          raise fault

        profile in ~w(stats_return stats_database) ->
          CalculateMonth.call(
            repo,
            id,
            year,
            3,
            Keyword.put(opts, :hexagons, fn _, _, _, _ -> raise fault end)
          )

        true ->
          CalculateMonth.call(repo, id, year, month, opts)
      end
    end

    calculate = fn repo, id, year, month, opts ->
      record.(repo, id, %{"kind" => "digest"})

      if profile in ~w(digest_raise digest_database) do
        {:error, fault, Enum.map(1..25, &"synthetic frame #{&1}")}
      else
        if kase["kind"] == "monthly",
          do: Calculation.monthly(repo, id, year, month, opts),
          else: Calculation.yearly(repo, id, year, opts)
      end
    end

    F.job_options(kase) ++
      [
        stats: stats,
        monthly: calculate,
        yearly: fn repo, id, year, opts -> calculate.(repo, id, year, nil, opts) end
      ]
  end

  defp drain_calls(acc) do
    receive do
      {:call, call} -> drain_calls([call | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp arguments(payload, "monthly"), do: [payload["user_id"], payload["year"], payload["month"]]
  defp arguments(payload, "yearly"), do: [payload["user_id"], payload["year"]]

  defp message_prefix(body) do
    [_, prefix, stack] =
      Regex.run(~r/^(.*?(?:stacktrace: |trace d’appels : |détail de l'erreur : ))(.*)$/su, body)

    assert String.trim(stack) != ""
    prefix
  end
end
