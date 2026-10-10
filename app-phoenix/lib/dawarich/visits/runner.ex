defmodule Dawarich.Visits.Runner do
  @moduledoc false

  require Logger

  alias Dawarich.{Geo, RailsEffects}
  alias Dawarich.Geocoding.Config

  alias Dawarich.Visits.{
    Calendar,
    CandidateLoader,
    DwellSweep,
    GapBridger,
    MovementReconciler,
    PlaceAttributor,
    Persister,
    Settings,
    Sql,
    StayAssembler,
    StayScoring,
    VisitRescore
  }

  @batch_threshold_days 31

  def run(repo, user, start, stop, zone) do
    started = System.monotonic_time(:millisecond)
    ctx = context(repo, user, zone)
    {start, stop} = window(ctx, start, stop)

    {created, skipped} =
      ctx
      |> batches(start, stop)
      |> Enum.reduce({[], []}, fn batch, {created, skipped} ->
        case run_batch(ctx, batch) do
          :skipped -> {created, skipped ++ [batch]}
          visits -> {created ++ visits, skipped}
        end
      end)

    created = stitch(ctx, created)

    Logger.info(
      "[Visits::Detection::Runner] user_id=#{user.id} range=#{start}..#{stop} version=3 " <>
        "visits=#{length(created)} duration_ms=#{System.monotonic_time(:millisecond) - started}"
    )

    {created, skipped}
  end

  def context(repo, user, zone),
    do: %{
      repo: repo,
      user_id: user.id,
      zone: zone,
      policy: Settings.policy(Dawarich.UserSettings.get(user)),
      config: Config.resolve(repo),
      areas: PlaceAttributor.areas(repo, user.id)
    }

  def window(ctx, start, stop) do
    [[earliest, latest]] =
      ctx.repo.query!(
        "SELECT floor(extract(epoch FROM min(v.started_at)))::bigint, floor(extract(epoch FROM max(v.ended_at)))::bigint " <>
          "FROM visits v WHERE #{Sql.machine("v")} AND v.user_id = $1 AND v.started_at <= $2 AND v.ended_at >= $3",
        [ctx.user_id, naive(stop), naive(start)],
        log: false
      ).rows

    {if(earliest, do: min(start, earliest), else: start),
     if(latest, do: max(stop, latest), else: stop)}
  end

  def batches(ctx, start, stop) do
    if Integer.floor_div(stop - start, 86_400) <= @batch_threshold_days,
      do: [[start, stop]],
      else: Calendar.month_batches(ctx.repo, ctx.zone, start, stop)
  end

  def attribute_and_score(ctx, stays, points_by_id) do
    for stay <- stays do
      attributed = Map.merge(stay, PlaceAttributor.attribute(ctx, stay))
      Map.merge(attributed, StayScoring.attributes(attributed, points_by_id, ctx.policy))
    end
  end

  defp run_batch(ctx, [bs, be]) do
    evidence = CandidateLoader.load(ctx.repo, ctx.user_id, bs, be)

    if evidence.skipped do
      :skipped
    else
      by_id = Map.new(evidence.points, &{&1.id, &1})
      stays = if evidence.points == [], do: [], else: stays(evidence, by_id, ctx.policy)
      scored = if stays == [], do: [], else: attribute_and_score(ctx, stays, by_id)
      refresh = fn prepared -> refresh(ctx, bs, be, evidence, prepared) end
      Persister.run(ctx.repo, ctx.user_id, bs, be, scored, by_id, ctx.policy, refresh)
    end
  end

  defp refresh(ctx, start, stop, evidence, prepared) do
    require_current_context(ctx)
    {bs, be} = window(ctx, start, stop)
    current = CandidateLoader.load(ctx.repo, ctx.user_id, bs, be)

    cond do
      current.skipped ->
        ctx.repo.rollback(:candidate_limit)

      {bs, be, current} == {start, stop, evidence} ->
        prepared

      true ->
        by_id = Map.new(current.points, &{&1.id, &1})

        scored =
          current
          |> stays(by_id, ctx.policy)
          |> attribute_and_score_current(ctx, by_id)

        {bs, be, scored, by_id}
    end
  end

  defp require_current_context(ctx) do
    case Settings.load(ctx.repo, ctx.user_id) do
      nil ->
        ctx.repo.rollback(:stale_context)

      user ->
        if context(ctx.repo, user, ctx.zone) != ctx, do: ctx.repo.rollback(:stale_context)
    end
  end

  defp attribute_and_score_current(stays, ctx, by_id) do
    ctx = %{ctx | areas: PlaceAttributor.areas(ctx.repo, ctx.user_id)}
    attribute_and_score(ctx, stays, by_id)
  end

  defp stays(evidence, by_id, policy) do
    evidence.points
    |> DwellSweep.run(policy)
    |> GapBridger.run(policy)
    |> MovementReconciler.run(evidence.segments, policy)
    |> StayAssembler.run(by_id, policy)
  end

  defp stitch(_ctx, created) when length(created) < 2, do: created

  defp stitch(ctx, created) do
    case ctx.repo.transaction(fn ->
           Persister.lock(ctx.repo, ctx.user_id)
           require_current_context(ctx)
           require_current_visits(ctx, created)
           stitch_current(ctx, created)
         end) do
      {:ok, visits} -> visits
      {:error, :stale_context} -> []
    end
  end

  defp require_current_visits(ctx, created) do
    current =
      ctx.repo.query!(
        "SELECT v.id, floor(extract(epoch FROM v.started_at))::bigint, floor(extract(epoch FROM v.ended_at))::bigint, v.place_id, v.area_id " <>
          "FROM visits v WHERE v.user_id=$1 AND v.id=ANY($2) AND v.deleted_at IS NULL AND v.status=0 AND v.import_id IS NULL AND v.demo=false " <>
          "AND NOT EXISTS (SELECT 1 FROM notes WHERE attachable_type='Visit' AND attachable_id=v.id) ORDER BY v.id FOR UPDATE",
        [ctx.user_id, Enum.map(created, & &1.id)],
        log: false
      ).rows

    expected =
      created
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&[&1.id, &1.started_at, &1.ended_at, &1.place_id, &1.area_id])

    if current != expected, do: ctx.repo.rollback(:stale_context)
  end

  defp stitch_current(ctx, created) do
    centers =
      Map.new(
        created,
        &{&1.id, VisitRescore.center(ctx.repo, &1, VisitRescore.points(ctx.repo, &1.id))}
      )

    created
    |> Enum.sort_by(& &1.started_at)
    |> Enum.reduce([], fn visit, survivors ->
      case survivors do
        [previous | rest] ->
          if stitchable?(ctx, previous, visit, centers),
            do: [absorb(ctx, previous, visit) | rest],
            else: [visit | survivors]

        [] ->
          [visit]
      end
    end)
    |> Enum.reverse()
  end

  defp stitchable?(ctx, previous, visit, centers) do
    gap = visit.started_at - previous.ended_at

    cond do
      gap > ctx.policy.bridge_cap_s -> false
      Geo.distance_m(centers[previous.id], centers[visit.id]) > ctx.policy.stay_radius_m -> false
      anchor_between?(ctx, previous.ended_at, visit.started_at) -> false
      gap <= ctx.policy.merge_gap_s -> true
      true -> no_points_between?(ctx, previous.ended_at, visit.started_at)
    end
  end

  defp anchor_between?(ctx, from, to),
    do:
      ctx.repo.query!(
        "SELECT EXISTS (SELECT 1 FROM visits v WHERE v.user_id = $1 AND #{Sql.anchor("v", "$1")} " <>
          "AND v.started_at < $2 AND v.ended_at > $3)",
        [ctx.user_id, naive(to), naive(from)],
        log: false
      ).rows == [[true]]

  defp no_points_between?(ctx, from, to),
    do:
      ctx.repo.query!(
        "SELECT NOT EXISTS (SELECT 1 FROM points WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3)",
        [ctx.user_id, from + 1, to - 1],
        log: false
      ).rows == [[true]]

  defp absorb(ctx, previous, visit) do
    repo = ctx.repo
    survivor = %{previous | ended_at: visit.ended_at}

    {:ok, _} =
      repo.transaction(fn ->
        repo.query!(
          "UPDATE points SET visit_id = $1 WHERE visit_id = $2",
          [previous.id, visit.id],
          log: false
        )

        repo.query!(
          "UPDATE visits SET ended_at = $2, duration = $3, updated_at = now() WHERE id = $1",
          [previous.id, naive(visit.ended_at), div(visit.ended_at - previous.started_at, 60)],
          log: false
        )

        repo.query!("DELETE FROM place_visits WHERE visit_id = $1", [visit.id], log: false)

        repo.query!(
          "DELETE FROM notes WHERE attachable_type = 'Visit' AND attachable_id = $1",
          [visit.id],
          log: false
        )

        repo.query!("DELETE FROM visits WHERE id = $1", [visit.id], log: false)

        RailsEffects.visit_months(
          repo,
          ctx.user_id,
          Enum.map([previous.started_at, visit.started_at], &DateTime.from_unix!/1)
        )

        RailsEffects.orphan_places(repo, ctx.user_id, List.wrap(visit.place_id))
      end)

    VisitRescore.run(repo, survivor, ctx.policy)
    survivor
  end

  defp naive(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_naive()
end
