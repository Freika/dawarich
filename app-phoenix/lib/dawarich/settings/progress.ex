defmodule Dawarich.Settings.Progress do
  @moduledoc false
  alias Dawarich.{State, RubyInteger}
  alias Dawarich.Settings.Api
  alias Dawarich.Transportation.RecalculationStatus
  @keys ~w(status total_tracks processed_tracks started_at completed_at error_message)

  def show(user, ctx) do
    with :ok <- Api.guard(user, ctx, true) do
      data = RecalculationStatus.data(user.id)
      {:ok, 200, Map.new(@keys, &{&1, data[&1]})}
    end
  rescue
    _ -> {:error, 500, Api.failure()}
  end

  def rebucket(repo, user, before, after_settings, ctx) do
    if before["timezone"] != after_settings["timezone"] do
      repo.query!(
        "UPDATE stats SET calculation_version=0,repair_deferred_at=$2 WHERE user_id=$1 RETURNING year,month",
        [user, DateTime.to_naive(ctx.now)],
        log: false
      ).rows
    else
      []
    end
  end

  def rebuild(repo, user, months, ctx) do
    for [year, month] <- months do
      produce(
        repo,
        "stats.calculate_month",
        %{"user_id" => user, "year" => year, "month" => month, "notify_on_failure" => false},
        user,
        ctx
      )
    end
  end

  def callbacks(repo, user, before, after_settings, attrs, ctx) do
    modes =
      Map.has_key?(attrs, "enabled_transportation_modes") and
        Enum.sort(Api.effective_modes(before["enabled_transportation_modes"])) !=
          Enum.sort(Api.effective_modes(after_settings["enabled_transportation_modes"]))

    city =
      Map.has_key?(attrs, "min_minutes_spent_in_city") and
        RubyInteger.to_i(before["min_minutes_spent_in_city"] || 60) !=
          RubyInteger.to_i(after_settings["min_minutes_spent_in_city"] || 60)

    if modes, do: produce(repo, "transportation.user_reclassify", %{"user_id" => user}, user, ctx)

    if city do
      {:ok, :ok} =
        repo.transaction(fn ->
          if State.debounce(repo, "stats_full_recalculation:user:#{user}", 300),
            do:
              produce(
                repo,
                "stats.full_recalculation",
                %{"user_id" => user, "source_job_id" => Ecto.UUID.generate()},
                user,
                Map.put(ctx, :now, DateTime.add(ctx.now, 60))
              )

          if State.claim(repo, "achievements_check:user:#{user}", 3600),
            do:
              produce(
                repo,
                "achievements.check",
                %{"user_id" => user, "notify" => true, "oldest_timestamp" => nil},
                user,
                Map.put(ctx, :now, DateTime.add(ctx.now, 60))
              )

          :ok
        end)
    end

    modes or city
  end

  def produce(repo, kind, payload, aggregate, ctx) do
    {:ok, :ok} =
      repo.transaction(fn ->
        if Dawarich.Jobs.Ownership.lock(repo, "command:" <> kind) != :oban,
          do: raise("native producer owner unavailable")

        repo.query!(
          "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6)",
          [
            Ecto.UUID.bingenerate(),
            kind,
            payload,
            %{"producer" => "Phoenix Settings API"},
            aggregate,
            ctx.now
          ],
          log: false
        )

        :ok
      end)

    :ok
  end
end
