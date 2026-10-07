defmodule Dawarich.Stats.CalculateMonth do
  @moduledoc false

  require Logger

  alias Dawarich.{I18n, Notifications}
  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.Stats.{Accounts, GeocodedDays, Hexagons, MonthQueries}

  @version 3
  @lock "SELECT id FROM stats WHERE user_id = $1 AND year = $2 AND month = $3 ORDER BY id LIMIT 1 FOR UPDATE"
  @insert """
  INSERT INTO stats (user_id, year, month, distance, sharing_uuid, created_at, updated_at)
  VALUES ($1, $2, $3, 0, gen_random_uuid(), $4, $4) RETURNING id
  """
  @update """
  UPDATE stats SET daily_distance = $2, distance = $3, flight_distance = $4, toponyms = $5,
    h3_hex_ids = $6, calculation_version = #{@version}, updated_at = $7
  WHERE id = $1
    AND (daily_distance, distance, flight_distance, toponyms, h3_hex_ids, calculation_version)
      IS DISTINCT FROM ($2::jsonb, $3::bigint, $4::bigint, $5::jsonb, $6::jsonb, #{@version})
  """
  @reset """
  UPDATE stats SET daily_distance = '{}', distance = 0, flight_distance = $2, toponyms = '[]',
    h3_hex_ids = '{}', calculation_version = #{@version}, updated_at = $3
  WHERE id = $1
    AND (daily_distance, distance, flight_distance, toponyms, h3_hex_ids, calculation_version)
      IS DISTINCT FROM ('{}'::jsonb, 0::bigint, $2::bigint, '[]'::jsonb, '{}'::jsonb, #{@version})
  """

  def call(repo, user_id, year, month, opts \\ []) do
    case Accounts.find(repo, user_id) do
      nil ->
        :missing

      user ->
        run(%{
          repo: repo,
          user: user,
          year: year,
          month: month,
          opts: opts,
          now: Keyword.get_lazy(opts, :now, &NaiveDateTime.utc_now/0),
          clock: Keyword.get_lazy(opts, :clock, fn -> System.os_time(:second) end)
        })
    end
  end

  defp run(ctx) do
    window = MonthQueries.window(ctx.year, ctx.month)

    if MonthQueries.exists?(ctx.repo, ctx.user.id, window),
      do: update!(ctx, window),
      else: reset!(ctx, window)

    :ok
  rescue
    error -> fail(ctx, error, __STACKTRACE__)
  end

  defp update!(%{repo: repo, user: user, year: year, month: month} = ctx, window) do
    {:ok, :ok} =
      repo.transaction(fn ->
        fence!(ctx)
        id = locked(ctx) || insert!(ctx)
        pending = GeocodedDays.snapshot_month(repo, user.id, user.zone, year, month)
        daily = MonthQueries.daily(repo, user, year, month, window)
        hexagons = Keyword.get(ctx.opts, :hexagons, &Hexagons.calculate/4)

        repo.query!(
          @update,
          [
            id,
            daily,
            daily |> Enum.map(&List.last/1) |> Enum.sum(),
            MonthQueries.flight_distance(repo, user, year, month),
            MonthQueries.toponyms(repo, user, year, month, window),
            hexagons.(repo, user, year, month),
            ctx.now
          ],
          log: false
        )

        invalidated!(ctx)
        GeocodedDays.acknowledge(repo, pending, ctx.clock)
        fence!(ctx)
      end)

    :ok
  end

  defp reset!(%{repo: repo, user: user, year: year, month: month} = ctx, window) do
    {:ok, :ok} =
      repo.transaction(fn ->
        fence!(ctx)

        case locked(ctx) do
          nil ->
            :ok

          id ->
            if MonthQueries.exists?(repo, user.id, window) do
              update!(ctx, window)
            else
              flight = MonthQueries.flight_distance(repo, user, year, month)
              repo.query!(@reset, [id, flight, ctx.now], log: false)
              invalidated!(ctx)
            end
        end

        fence!(ctx)
      end)

    :ok
  end

  defp locked(ctx) do
    case ctx.repo.query!(@lock, [ctx.user.id, ctx.year, ctx.month], log: false).rows do
      [[id]] -> id
      [] -> nil
    end
  end

  defp insert!(ctx) do
    %{rows: [[id]]} =
      ctx.repo.query!(@insert, [ctx.user.id, ctx.year, ctx.month, ctx.now], log: false)

    id
  end

  defp invalidated!(ctx) do
    case Keyword.get(ctx.opts, :invalidated) do
      nil ->
        Dawarich.Stats.CacheInvalidation.call(ctx.repo, %{
          "user_id" => ctx.user.id,
          "year" => ctx.year,
          "scope" => "all"
        })

      callback ->
        callback.()
    end
  end

  defp fail(ctx, error, stacktrace) do
    message = Exception.message(error)

    Logger.error(
      "Stats::CalculateMonth failed for user #{ctx.user.id} #{ctx.year}-#{ctx.month}: #{inspect(error.__struct__)}: #{message}"
    )

    if Keyword.get(ctx.opts, :notify, true),
      do: notify!(ctx, message, Exception.format_stacktrace(stacktrace))

    {:error, error}
  end

  defp notify!(%{repo: repo, user: user} = ctx, message, backtrace) do
    locale = ExploreFeatures.locale(Dawarich.UserSettings.get(user), nil)
    {:ok, title} = I18n.t(locale, "services.stats.calculate_month.stats_update_failed")

    {:ok, content} =
      I18n.t(locale, "services.stats.calculate_month.message_stacktrace_n", %{
        "message" => message,
        "backtrace" => backtrace
      })

    {:ok, _} =
      repo.transaction(fn ->
        fence!(ctx)
        result = Notifications.create!(repo, user.id, :error, title, content)
        fence!(ctx)
        result
      end)
  end

  defp fence!(ctx) do
    if fence = ctx.opts[:fence], do: fence.(), else: :ok
  end
end
