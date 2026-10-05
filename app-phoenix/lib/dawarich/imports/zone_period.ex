defmodule Dawarich.Imports.ZonePeriod do
  @moduledoc false
  alias Dawarich.Imports.ZoneRules
  @root "/usr/share/zoneinfo"
  @name ~r/\A[A-Za-z0-9_+\-]+(?:\/[A-Za-z0-9_+\-]+)*\z/

  def with_cache(fun) do
    key = {__MODULE__, :cache}
    previous = Process.put(key, %{})

    try do
      fun.()
    after
      if previous, do: Process.put(key, previous), else: Process.delete(key)
    end
  end

  def load!(zone) do
    unless zone =~ @name, do: raise(ArgumentError, "invalid time zone")

    case Process.get({__MODULE__, :cache}) do
      nil ->
        read!(zone)

      cache ->
        case Map.fetch(cache, zone) do
          {:ok, data} ->
            data

          :error ->
            data = read!(zone)
            Process.put({__MODULE__, :cache}, Map.put(cache, zone, data))
            data
        end
    end
  end

  defp read!(zone) do
    bytes = File.read!(Path.join(@root, zone))
    {version, counts, block} = header(bytes)

    if version in [?2, ?3, ?4] do
      skip = size(counts, 4)
      <<_first::binary-size(skip), next::binary>> = block
      {_v, counts, block} = header(next)
      decode(counts, block, 8)
    else
      decode(counts, block, 4)
    end
  end

  def local_now(zone, %DateTime{} = now) do
    {offset, _dst} = offset(zone, DateTime.to_unix(now), now.year)
    now |> DateTime.to_naive() |> NaiveDateTime.add(offset)
  end

  def resolve(zone, naive) do
    wall = naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

    Enum.find_value(0..24, fn hours ->
      local = wall + hours * 3600

      candidates =
        for delta <- zone.offsets,
            epoch = local - delta,
            {^delta, dst} <- [offset(zone, epoch, naive.year)],
            do: {epoch, dst}

      candidates = Enum.sort(candidates)
      daylight = Enum.filter(candidates, &elem(&1, 1))
      candidates = if daylight == [], do: candidates, else: daylight

      case List.last(candidates) do
        {epoch, _dst} -> epoch
        nil -> nil
      end
    end) || raise(ArgumentError, "invalid local time")
  end

  defp offset(zone, epoch, year) do
    _ = year
    elem(zone.types, index(zone.transitions, epoch, 0, tuple_size(zone.transitions) - 1, 0))
  end

  defp index(_transitions, _epoch, lo, hi, found) when lo > hi, do: found

  defp index(transitions, epoch, lo, hi, found) do
    middle = div(lo + hi, 2)
    {at, type} = elem(transitions, middle)

    if epoch >= at,
      do: index(transitions, epoch, middle + 1, hi, type),
      else: index(transitions, epoch, lo, middle - 1, found)
  end

  defp header(
         <<"TZif", version, _reserved::binary-size(15), gmt::32, std::32, leap::32, time::32,
           type::32, chars::32, block::binary>>
       ) do
    {version, %{gmt: gmt, std: std, leap: leap, time: time, type: type, chars: chars}, block}
  end

  defp size(c, width),
    do: c.time * (width + 1) + c.type * 6 + c.chars + c.leap * (width + 4) + c.std + c.gmt

  defp decode(c, block, width) do
    len = c.time * width
    types_len = c.type * 6
    remaining = size(c, width) - len - c.time - types_len

    <<times::binary-size(len), indices::binary-size(c.time), types::binary-size(types_len),
      _metadata::binary-size(remaining), footer::binary>> = block

    timestamps =
      if width == 8,
        do: for(<<t::signed-64 <- times>>, do: t),
        else: for(<<t::signed-32 <- times>>, do: t)

    types = for <<offset::signed-32, daylight, _abbr <- types>>, do: {offset, daylight == 1}
    transitions = Enum.zip(timestamps, :binary.bin_to_list(indices))
    rules = footer |> String.trim("\n") |> ZoneRules.parse()
    {types, transitions} = extend(types, transitions, rules)

    offsets =
      Enum.map(types, &elem(&1, 0)) ++ if(rules, do: [rules.standard, rules.daylight], else: [])

    %{
      types: List.to_tuple(types),
      transitions: List.to_tuple(transitions),
      last: List.last(timestamps),
      offsets: Enum.uniq(offsets),
      rules: rules
    }
  end

  defp extend(types, transitions, nil), do: {types, transitions}

  defp extend(types, transitions, rules) do
    last =
      case List.last(transitions) do
        {at, _} -> at
        nil -> DateTime.to_unix(~U[1969-12-31 23:59:59Z])
      end

    year = DateTime.from_unix!(last).year
    horizon = Date.utc_today().year + 100

    if year > horizon do
      {types, transitions}
    else
      types = types ++ [{rules.standard, false}, {rules.daylight, true}]

      generated =
        for y <- year..horizon,
            {at, type} <- ZoneRules.transitions(y, rules),
            at > last,
            do: {at, Enum.find_index(types, &(&1 == type))}

      {types, transitions ++ generated}
    end
  end
end
