defmodule Dawarich.Stats.ToponymsRefresh do
  @moduledoc false

  require Logger

  alias Dawarich.{RubyInteger, State}
  alias Dawarich.Stats.{Accounts, GeocodedDays, RefreshToponyms, Schedule}

  @discovery "stats:toponyms_reconciliation:missing_cursor"
  @turn "stats:toponyms_reconciliation:turn"
  @cursor "stats:toponyms_reconciliation:cursor"
  @months 10
  @reconciliations 2
  @budget_ms 30_000
  @earliest -2_147_483_648
  @first_point """
  SELECT timestamp FROM points WHERE user_id = $1 AND (anomaly = FALSE OR anomaly IS NULL)
    AND timestamp >= $2::bigint ORDER BY timestamp LIMIT 1
  """
  @month_of """
  SELECT extract(year FROM t)::int, extract(month FROM t)::int,
    extract(epoch FROM (date_trunc('month', t) + interval '1 month') AT TIME ZONE $2)::bigint
  FROM (SELECT to_timestamp($1) AT TIME ZONE $2 AS t) AS local
  """
  @stat_exists "SELECT EXISTS (SELECT 1 FROM stats WHERE user_id = $1 AND year = $2 AND month = $3)"
  @next_stats "SELECT id, user_id, year, month FROM stats WHERE id > $1 ORDER BY id LIMIT #{@reconciliations}"

  def run(repo, opts \\ []) do
    deadline =
      Keyword.get_lazy(opts, :deadline, fn -> System.monotonic_time(:millisecond) + @budget_ms end)

    st = %{
      repo: repo,
      opts: opts,
      deadline: deadline,
      remaining: @months,
      results: %{},
      scheduled: MapSet.new()
    }

    st = discover(st)

    if rem(State.increment_cursor(repo, @turn), 2) == 1 do
      st |> reconcile() |> Map.put(:results, %{}) |> refresh_pending()
    else
      st = refresh_pending(%{st | remaining: st.remaining - @reconciliations})
      st = %{st | remaining: @reconciliations}
      if within_budget?(st), do: reconcile(st)
    end

    :ok
  end

  defp discover(%{repo: repo} = st) do
    {user_id, from} =
      case State.cursor(repo, @discovery) do
        nil -> {0, @earliest}
        raw -> raw |> Jason.decode!() |> List.to_tuple()
      end

    case Accounts.first_from(repo, user_id) do
      nil ->
        State.delete_cursor(repo, @discovery)
        st

      account ->
        from = if account.id == user_id, do: from, else: @earliest

        case repo.query!(@first_point, [account.id, from], log: false).rows do
          [] ->
            put_discovery(repo, [account.id + 1, @earliest])
            st

          [[first]] ->
            [[year, month, next]] = repo.query!(@month_of, [first, account.zone], log: false).rows
            [[exists]] = repo.query!(@stat_exists, [account.id, year, month], log: false).rows

            st =
              if exists,
                do: st,
                else: schedule_full(%{st | remaining: st.remaining - 1}, account.id, year, month)

            put_discovery(repo, [account.id, next])
            st
        end
    end
  end

  defp reconcile(%{repo: repo} = st) do
    cursor = RubyInteger.to_i(State.cursor(repo, @cursor))

    case repo.query!(@next_stats, [cursor], log: false).rows do
      [] ->
        State.put_cursor(repo, @cursor, "0")
        st

      rows ->
        Enum.reduce_while(rows, st, fn [id, user_id, year, month], st ->
          if within_budget?(st) do
            st =
              case Accounts.find(repo, user_id) do
                nil -> st
                account -> st |> refresh(account, year, month, false) |> elem(0)
              end

            State.put_cursor(repo, @cursor, Integer.to_string(id))
            {:cont, st}
          else
            {:halt, st}
          end
        end)
    end
  end

  defp refresh_pending(%{repo: repo} = st) do
    {st, _accounts} =
      repo
      |> GeocodedDays.due(@months * 31, clock(st))
      |> Enum.reduce_while({st, %{}}, fn {member, version}, {st, accounts} ->
        if time_remaining?(st),
          do: pending(st, accounts, member, version),
          else: {:halt, {st, accounts}}
      end)

    st
  end

  defp pending(%{repo: repo} = st, accounts, member, version) do
    user_id = member |> String.split(":", parts: 2) |> hd() |> RubyInteger.to_i()
    {account, accounts} = cached(repo, accounts, user_id)

    if account do
      months = GeocodedDays.local_months(repo, member, account.zone)

      needed =
        Enum.count(months, fn {year, month} ->
          not Map.has_key?(st.results, {account.id, year, month})
        end)

      if needed > st.remaining do
        {:halt, {st, accounts}}
      else
        {st, refreshed} = refresh_all(st, account, months)

        if refreshed,
          do: GeocodedDays.acknowledge(repo, [{member, version}], clock(st)),
          else: GeocodedDays.postpone(repo, member, clock(st))

        {:cont, {st, accounts}}
      end
    else
      GeocodedDays.acknowledge(repo, [{member, version}], clock(st))
      {:cont, {st, accounts}}
    end
  end

  defp refresh_all(st, account, months) do
    Enum.reduce_while(months, {st, true}, fn {year, month}, {st, true} ->
      case refresh(st, account, year, month, true) do
        {st, true} -> {:cont, {st, true}}
        {st, false} -> {:halt, {st, false}}
      end
    end)
  end

  defp refresh(st, account, year, month, invalidate) do
    key = {account.id, year, month}

    cond do
      Map.has_key?(st.results, key) -> {st, st.results[key]}
      not within_budget?(st) -> {st, false}
      true -> attempt(%{st | remaining: st.remaining - 1}, account, key, invalidate)
    end
  end

  defp attempt(st, account, {_user_id, year, month} = key, invalidate) do
    refresh = Keyword.get(st.opts, :refresh, &RefreshToponyms.call/6)

    if refresh.(st.repo, account, year, month, invalidate, st.opts) do
      {put_in(st.results[key], true), true}
    else
      st = schedule_full(st, account.id, year, month)
      {put_in(st.results[key], false), false}
    end
  rescue
    error ->
      Logger.error(
        "Toponym refresh failed for user #{account.id} #{year}-#{month}: #{inspect(error.__struct__)}: #{Exception.message(error)}"
      )

      {put_in(st.results[key], false), false}
  end

  defp schedule_full(st, user_id, year, month) do
    key = {user_id, year, month}

    if MapSet.member?(st.scheduled, key) do
      st
    else
      Schedule.calculate(st.repo, user_id, year, month, false, st.opts)
      %{st | scheduled: MapSet.put(st.scheduled, key)}
    end
  end

  defp cached(repo, accounts, user_id) do
    case Map.fetch(accounts, user_id) do
      {:ok, account} ->
        {account, accounts}

      :error ->
        account = Accounts.find(repo, user_id)
        {account, Map.put(accounts, user_id, account)}
    end
  end

  defp put_discovery(repo, cursor), do: State.put_cursor(repo, @discovery, Jason.encode!(cursor))
  defp within_budget?(st), do: st.remaining > 0 and time_remaining?(st)
  defp time_remaining?(st), do: System.monotonic_time(:millisecond) < st.deadline
  defp clock(st), do: Keyword.get_lazy(st.opts, :clock, fn -> System.os_time(:second) end)
end
