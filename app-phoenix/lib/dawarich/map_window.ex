defmodule Dawarich.MapWindow do
  @moduledoc false

  alias Dawarich.{LocalTime, Repo, TimeZoneName, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Imports.{ImportTime, ZonePeriod}
  alias Dawarich.MapApi.RailsDate

  @iso ~r/\A\s*(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?\s*\z/
  @max_epoch 253_402_300_799

  defdelegate user_zone(settings, env), to: UserTimeZone, as: :zone

  def iso?(value), do: Regex.match?(@iso, value)

  defdelegate local_utc(naive, zone, repo \\ Repo), to: Dawarich.MapWindow.Convert

  def build(params, settings, now, import_range, env \\ System.get_env()) do
    main = UserTimeZone.name(settings, Repo, env)
    names = zone_names(settings, env)
    valid = names |> Map.values() |> Enum.uniq() |> valid_zones()
    ctx = %{main: main, day: pick([names.day], valid, main), now: DateTime.to_unix(now)}

    head = [
      {:epoch, ctx.now, main},
      {:epoch, ctx.now, ctx.day} | import_specs(import_range, main)
    ]

    limits = [local(~N[1970-01-01 00:00:00], main), local(~N[2100-01-01 00:00:00], main)]

    {[now_main, now_day | imports], {first, first_clamped}, {last, last_clamped}, [f, l, lo, hi]} =
      if explicit?(params, "start_at") and explicit?(params, "end_at") do
        first = timestamp(params["start_at"], ctx)
        last = timestamp(params["end_at"], ctx)

        {heads, tail} =
          head
          |> Kernel.++([elem(first, 0), elem(last, 0) | limits])
          |> points()
          |> Enum.split(length(head))

        {heads, first, last, tail}
      else
        heads = points(head)
        ctx = with_days(ctx, heads)
        first = bound(params, "start_at", ~T[00:00:00], ctx)
        last = bound(params, "end_at", ~T[23:59:59], ctx)
        {heads, first, last, points([elem(first, 0), elem(last, 0) | limits])}
      end

    ctx = with_days(ctx, [now_main, now_day | imports])

    known =
      for {t, spec} <- Enum.zip([f, l, lo, hi], [first, last | limits]),
          elem(spec, 2) == main,
          do: t

    start_epoch = clamp(elem(f, 0), first_clamped, elem(lo, 0), elem(hi, 0))
    end_epoch = clamp(elem(l, 0), last_clamped, elem(lo, 0), elem(hi, 0))
    [s, e] = at_epochs([start_epoch, end_epoch], known, main)
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

  defp valid_zones(names),
    do: names |> Enum.filter(&Dawarich.TimeZoneNames.member?(Repo, &1)) |> MapSet.new()

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
    if Regex.match?(~r/\A\d+\z/, value) do
      {{:epoch, min(String.to_integer(value), @max_epoch), ctx.main}, true}
    else
      epoch = ImportTime.parse(value, ctx.main, DateTime.from_unix!(ctx.now))

      suspicious =
        epoch != nil and not String.contains?(value, "2000") and
          ZonePeriod.local_now(ZonePeriod.load!(ctx.main), DateTime.from_unix!(epoch)).year ==
            2000

      if epoch == nil or suspicious,
        do: {{:epoch, ctx.now, ctx.main}, false},
        else: {{:epoch, epoch, ctx.main}, true}
    end
  rescue
    _error in [ArgumentError, FunctionClauseError] -> {{:epoch, ctx.now, ctx.main}, false}
  end

  defp requested_day(value, ctx) when is_binary(value) do
    cond do
      not Ruby.present?(value) -> nil
      value == "today" -> ctx.today_day
      true -> parse_day(value, ctx.today_day)
    end
  end

  defp requested_day(_value, _ctx), do: nil

  defp parse_day(value, today) do
    case RailsDate.parse(value, today) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp calendar_month(params, ctx) do
    source =
      Enum.find([params["date"], params["start_at"]], &(is_binary(&1) and Ruby.present?(&1)))

    Calendar.strftime((source && parse_day(source, ctx.today_day)) || ctx.today_day, "%Y-%m")
  end

  defp explicit?(params, key), do: is_binary(params[key]) and Ruby.present?(params[key])

  defp with_days(ctx, [now_main, now_day | imports]) do
    Map.merge(ctx, %{
      today: day_of(now_main),
      today_day: day_of(now_day),
      imports: Enum.map(imports, &day_of/1)
    })
  end

  defp at_epochs(epochs, known, zone) do
    found = Enum.map(epochs, fn epoch -> Enum.find(known, &(elem(&1, 0) == epoch)) end)
    if nil in found, do: points(Enum.map(epochs, &{:epoch, &1, zone})), else: found
  end

  defp clamp(value, true, lo, hi), do: value |> max(lo) |> min(hi)
  defp clamp(value, false, _lo, _hi), do: value

  defp local(naive, zone), do: {:local, naive, zone}

  defp points(specs), do: Dawarich.MapWindow.Convert.points(specs)

  defp naive({_e, local, _offset}), do: NaiveDateTime.from_iso8601!(local)
  defp day_of({_e, local, _offset}), do: local |> binary_part(0, 10) |> Date.from_iso8601!()

  defp iso({_e, local, offset}, zone), do: local <> LocalTime.offset(zone, offset, :iso)
end
