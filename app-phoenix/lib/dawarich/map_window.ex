defmodule Dawarich.MapWindow do
  @moduledoc false

  alias Dawarich.{LocalTime, Repo, TimeZoneName, UserTimeZone, ZoneDst}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @iso ~r/\A\s*(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?\s*\z/
  @day ~r/\A\s*(\d{4})-(\d{1,2})-(\d{1,2})/
  @max_epoch 253_402_300_799

  @valid "SELECT name FROM pg_timezone_names WHERE name = ANY($1::text[])"

  @points """
  SELECT r.e, to_char(to_timestamp(r.e) AT TIME ZONE r.z, 'YYYY-MM-DD"T"HH24:MI:SS'),
         extract(epoch FROM (to_timestamp(r.e) AT TIME ZONE r.z) - (to_timestamp(r.e) AT TIME ZONE 'UTC'))::int
  FROM unnest($1::bigint[], $2::text[]) WITH ORDINALITY AS r(e, z, i)
  ORDER BY r.i
  """

  @candidates """
  SELECT found.epochs, found.offsets
  FROM unnest($1::timestamp[], $2::text[]) WITH ORDINALITY AS u(l, z, i)
  CROSS JOIN LATERAL (
    SELECT array_agg(c.e ORDER BY c.e) AS epochs, array_agg(c.utoff ORDER BY c.e) AS offsets
    FROM (
      SELECT step.hours, extract(epoch FROM candidate.t)::bigint AS e,
             extract(epoch FROM offsets.delta)::int AS utoff,
             min(step.hours) OVER () AS first_hours
      FROM generate_series(0, 24) AS step(hours)
      CROSS JOIN LATERAL (
        SELECT DISTINCT (anchor.t AT TIME ZONE u.z) - (anchor.t AT TIME ZONE 'UTC') AS delta
        FROM (VALUES ((u.l AT TIME ZONE u.z) - interval '2 days'), (u.l AT TIME ZONE u.z),
                     ((u.l AT TIME ZONE u.z) + interval '2 days')) AS anchor(t)
      ) offsets
      CROSS JOIN LATERAL (
        SELECT ((u.l + make_interval(hours => step.hours)) AT TIME ZONE 'UTC') - offsets.delta AS t
      ) candidate
      WHERE (candidate.t AT TIME ZONE u.z) = u.l + make_interval(hours => step.hours)
    ) c
    WHERE c.hours = c.first_hours
  ) found
  ORDER BY u.i
  """

  defdelegate user_zone(settings, env), to: UserTimeZone, as: :zone

  def iso?(value), do: Regex.match?(@iso, value)

  def build(params, settings, now, import_range, env \\ System.get_env()) do
    %{rows: [[main]]} = UserTimeZone.query!("SELECT z.name FROM z", [], settings, env)
    names = zone_names(settings, env)
    valid = names |> Map.values() |> Enum.uniq() |> valid_zones()
    ctx = %{main: main, day: pick([names.day], valid, main), now: DateTime.to_unix(now)}

    [now_main, now_day | imports] =
      points([
        {:epoch, ctx.now, main},
        {:epoch, ctx.now, ctx.day} | import_specs(import_range, main)
      ])

    ctx =
      Map.merge(ctx, %{
        today: day_of(now_main),
        today_day: day_of(now_day),
        imports: Enum.map(imports, &day_of/1)
      })

    {first, first_clamped} = bound(params, "start_at", ~T[00:00:00], ctx)
    {last, last_clamped} = bound(params, "end_at", ~T[23:59:59], ctx)

    [f, l, lo, hi] =
      points([
        first,
        last,
        local(~N[1970-01-01 00:00:00], main),
        local(~N[2100-01-01 00:00:00], main)
      ])

    start_epoch = clamp(elem(f, 0), first_clamped, elem(lo, 0), elem(hi, 0))
    end_epoch = clamp(elem(l, 0), last_clamped, elem(lo, 0), elem(hi, 0))
    [s, e] = points([{:epoch, start_epoch, main}, {:epoch, end_epoch, main}])
    {s_l, e_l, n_l} = {naive(s), naive(e), naive(now_main)}

    [prev_s, prev_e, next_s, next_e, today_s, today_e, week_s, month_s] =
      points(
        Enum.map(
          [
            NaiveDateTime.add(s_l, -1, :day),
            NaiveDateTime.add(e_l, -1, :day),
            NaiveDateTime.add(s_l, 1, :day),
            NaiveDateTime.add(e_l, 1, :day),
            NaiveDateTime.new!(ctx.today, ~T[00:00:00]),
            NaiveDateTime.new!(ctx.today, ~T[23:59:59]),
            n_l
            |> NaiveDateTime.add(-7, :day)
            |> NaiveDateTime.to_date()
            |> NaiveDateTime.new!(~T[00:00:00]),
            n_l
            |> NaiveDateTime.shift(month: -1)
            |> NaiveDateTime.to_date()
            |> NaiveDateTime.new!(~T[00:00:00])
          ],
          &local(&1, main)
        )
      )

    %{
      zone: main,
      iana: pick([names.iana], valid, "Etc/UTC"),
      start: iso(s, main),
      end: iso(e, main),
      start_local: binary_part(elem(s, 1), 0, 16),
      end_local: binary_part(elem(e, 1), 0, 16),
      start_date: NaiveDateTime.to_date(s_l),
      end_date: NaiveDateTime.to_date(e_l),
      prev: {iso(prev_s, main), iso(prev_e, main)},
      next: {iso(next_s, main), iso(next_e, main)},
      prev_date: day_of(prev_s),
      next_date: day_of(next_s),
      today: {iso(today_s, main), iso(today_e, main)},
      week_start: iso(week_s, main),
      month_start: iso(month_s, main),
      calendar_month: calendar_month(params, ctx)
    }
  end

  defp zone_names(settings, env) do
    effective = UserTimeZone.zone(settings, env)
    config = env["TIME_ZONE"] || "Europe/Berlin"
    present = Ruby.present?(effective)

    %{
      day: if(present, do: TimeZoneName.to_iana(effective), else: "UTC"),
      iana: TimeZoneName.to_iana(if(present, do: effective, else: config))
    }
  end

  defp valid_zones(names), do: Repo.query!(@valid, [names]).rows |> List.flatten() |> MapSet.new()

  defp pick(names, valid, default), do: Enum.find(names, default, &MapSet.member?(valid, &1))

  defp import_specs(nil, _zone), do: []
  defp import_specs({min, max}, zone), do: [{:epoch, min, zone}, {:epoch, max, zone}]

  defp bound(params, key, time, ctx) do
    value = params[key]

    cond do
      is_binary(value) and Ruby.present?(value) ->
        timestamp(value, ctx)

      date = requested_day(params["date"], ctx) ->
        {local(NaiveDateTime.new!(date, time), ctx.day), false}

      ctx.imports != [] ->
        {local(NaiveDateTime.new!(import_day(ctx.imports, time), time), ctx.main), false}

      true ->
        {local(NaiveDateTime.new!(ctx.today, time), ctx.main), false}
    end
  end

  defp import_day([first, _last], ~T[00:00:00]), do: first
  defp import_day([_first, last], _time), do: last

  defp timestamp(value, ctx) do
    cond do
      Regex.match?(~r/\A\d+\z/, value) ->
        {{:epoch, min(String.to_integer(value), @max_epoch), ctx.main}, true}

      match = Regex.run(@iso, value) ->
        parsed(match, ctx)

      true ->
        {{:epoch, ctx.now, ctx.main}, false}
    end
  end

  defp parsed([_, y, m, d | rest], ctx) do
    [hh, mm, ss, offset] = Enum.map(0..3, &Enum.at(rest, &1, ""))

    with {:ok, date} <- Date.new(int(y), int(m), int(d)),
         {:ok, time} <- Time.new(int(hh), int(mm), int(ss)) do
      naive = NaiveDateTime.new!(date, time)

      case offset_seconds(offset) do
        nil ->
          {local(naive, ctx.main), true}

        seconds ->
          {{:epoch, DateTime.to_unix(DateTime.from_naive!(naive, "Etc/UTC")) - seconds, ctx.main},
           true}
      end
    else
      _ -> {{:epoch, ctx.now, ctx.main}, false}
    end
  end

  defp int(""), do: 0
  defp int(digits), do: String.to_integer(digits)

  defp offset_seconds(""), do: nil
  defp offset_seconds("Z"), do: 0

  defp offset_seconds(<<sign, hours::binary-size(2), rest::binary>>) do
    minutes = rest |> String.trim_leading(":") |> int()
    (String.to_integer(hours) * 3600 + minutes * 60) * if(sign == ?-, do: -1, else: 1)
  end

  defp requested_day(value, ctx) when is_binary(value) do
    cond do
      not Ruby.present?(value) -> nil
      value == "today" -> ctx.today_day
      true -> parse_day(value)
    end
  end

  defp requested_day(_value, _ctx), do: nil

  defp parse_day(value) do
    with [_, y, m, d] <- Regex.run(@day, value),
         {:ok, date} <- Date.new(int(y), int(m), int(d)) do
      date
    else
      _ -> nil
    end
  end

  defp calendar_month(params, ctx) do
    source =
      Enum.find([params["date"], params["start_at"]], &(is_binary(&1) and Ruby.present?(&1)))

    Calendar.strftime((source && parse_day(source)) || ctx.today_day, "%Y-%m")
  end

  defp clamp(value, true, lo, hi), do: value |> max(lo) |> min(hi)
  defp clamp(value, false, _lo, _hi), do: value

  defp local(naive, zone), do: {:local, naive, zone}

  defp points(specs) do
    {epochs, zones} =
      specs |> resolve() |> Enum.map(fn {:epoch, e, z} -> {e, z} end) |> Enum.unzip()

    Repo.query!(@points, [epochs, zones]).rows |> Enum.map(&List.to_tuple/1)
  end

  defp resolve(specs) do
    case for({:local, l, z} <- specs, do: {l, z}) do
      [] ->
        specs

      locals ->
        {naives, zones} = Enum.unzip(locals)
        rows = Repo.query!(@candidates, [naives, zones]).rows

        {resolved, []} =
          Enum.map_reduce(specs, rows, fn
            {:local, _l, z}, [[epochs, offsets] | rest] ->
              {{:epoch, ZoneDst.pick(z, Enum.zip(epochs, offsets)), z}, rest}

            spec, rest ->
              {spec, rest}
          end)

        resolved
    end
  end

  defp naive({_e, local, _offset}), do: NaiveDateTime.from_iso8601!(local)
  defp day_of({_e, local, _offset}), do: local |> binary_part(0, 10) |> Date.from_iso8601!()

  defp iso({_e, local, offset}, zone), do: local <> LocalTime.offset(zone, offset, :iso)
end
