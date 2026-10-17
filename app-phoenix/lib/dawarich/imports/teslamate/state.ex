defmodule Dawarich.Imports.Teslamate.State do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  @key "command:imports.teslamate_sync"
  @credentials ~w(teslamate_url teslamate_username teslamate_password teslamate_api_token teslamate_skip_ssl_verification)

  def load!(repo, id) do
    if Ownership.lock(repo, @key) != :oban, do: repo.rollback(:lost)

    [[stamp]] =
      repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [@key], log: false).rows

    case repo.query!(
           "SELECT settings,points_count,plan,active_until FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
           [id],
           log: false
         ).rows do
      [[settings, count, plan, active]] ->
        %{
          repo: repo,
          id: id,
          settings: Dawarich.UserSettings.safe(settings),
          points_count: count || 0,
          plan: plan,
          active_until: active,
          stamp: stamp
        }

      _ ->
        repo.rollback(:lost)
    end
  end

  def fence!(ctx) do
    lease =
      ctx.repo.query!(
        "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
        ["teslamate-sync:#{ctx.id}"],
        log: false
      ).rows

    if lease != [[ctx.holder, true]], do: ctx.repo.rollback(:lost)
    current = load!(ctx.repo, ctx.id)

    if current.stamp != ctx.stamp or
         Map.take(current.settings, @credentials) != Map.take(ctx.settings, @credentials),
       do: ctx.repo.rollback(:lost)

    current
  end

  def update!(ctx, values) do
    ctx.repo.query!(
      "UPDATE users SET settings=settings || $2::jsonb,updated_at=now() WHERE id=$1",
      [ctx.id, values],
      log: false
    )
  end

  def allowed?(ctx, now, true), do: is_integer(ctx.id) and is_struct(now, DateTime)

  def allowed?(ctx, now, false) do
    Dawarich.Entitlements.future?(ctx.active_until, now) and
      Dawarich.Entitlements.full_access?(ctx.repo, ctx, false, now) and
      ctx.points_count < 10_000_000
  end

  def limit(ctx, payloads) do
    current = fence!(ctx)

    if ctx.hosted do
      {payloads, false}
    else
      keys =
        ctx.repo.query!(
          "SELECT timestamp,ST_X(lonlat::geometry),ST_Y(lonlat::geometry) FROM points WHERE user_id=$1 AND timestamp=ANY($2)",
          [ctx.id, Enum.map(payloads, & &1.timestamp)],
          log: false
        ).rows
        |> MapSet.new(fn [t, x, y] -> {x, y, t, ctx.id} end)

      {accepted, _, _, truncated} =
        Enum.reduce(payloads, {[], keys, max(10_000_000 - current.points_count, 0), false}, fn p,
                                                                                               {acc,
                                                                                                keys,
                                                                                                slots,
                                                                                                cut} ->
          key = Dawarich.Ingest.Geo.dedup_key(Map.put(p, :user_id, ctx.id))

          cond do
            MapSet.member?(keys, key) -> {[p | acc], keys, slots, cut}
            slots > 0 -> {[p | acc], MapSet.put(keys, key), slots - 1, cut}
            true -> {acc, keys, slots, true}
          end
        end)

      {Enum.reverse(accepted), truncated}
    end
  end
end
