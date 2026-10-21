defmodule Dawarich.Imports.DateParts do
  @moduledoc false
  alias Dawarich.Imports.{DateCompact, DateOffsets, DateOrder}
  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)
  @days ~w(sun mon tue wed thu fri sat)
  @mon "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
  @era "c(?:e|\\.e\\.)|b(?:ce|\\.c\\.e\\.)|a(?:d|\\.d\\.)|b(?:c|\\.c\\.)"
  @time ~r/((?<!\d)\d+\s*(?:(?::\s*\d+(?:\s*:\s*\d+(?:[,.]\d*)?)?|h(?:\s*\d+m?(?:\s*\d+s?)?)?)(?:\s*[ap](?:m\b|\.m\.))?|[ap](?:m\b|\.m\.)))(?:\s*((?:gmt|utc?)?[-+]\d+(?:[,.:]\d+(?::\d+)?)?|(?-i:[[:alpha:].\s]+)(?:standard|daylight)\stime\b|(?-i:[[:alpha:]]+)(?:\sdst)?\b))?/i
  @clock ~r/\A(\d+)h?(?:\s*:?\s*(\d+)m?(?:\s*:?\s*(\d+)(?:[,.](\d+))?s?)?)?(?:\s*([ap])(?:m\b|\.m\.))?/i
  @date_patterns [
    {Regex.compile!(
       "('?((?<!\\d)\\d+))[^-\\d\\s]*\\s*(#{@mon})[^-\\d\\s']*(?:\\s*(?:\\b(#{@era})(?!(?<!\\.)[a-z]))?\\s*('?-?\\d+(?:(?:st|nd|rd|th)\\b)?))?",
       "i"
     ), :eu},
    {Regex.compile!(
       "\\b(#{@mon})[^-\\d\\s']*\\s*('?\\d+)[^-\\d\\s']*(?:\\s*+,?\\s*+(#{@era})?\\s*('?-?\\d+))?",
       "i"
     ), :us},
    {~r/('?[-+]?(?<!\d)\d+)-(\d+)-('?-?\d+)/, :ymd},
    {~r/\b([mtshr])(\d+)\.(\d+)\.(\d+)/i, :jis},
    {Regex.compile!("('?-?(?<!\\d)\\d+)-(#{@mon})[^-/.]*-('?-?\\d+)", "i"), :vms},
    {Regex.compile!("\\b(#{@mon})[^-/.]*-('?-?\\d+)(?:-('?-?\\d+))?", "i"), :vms_us},
    {~r/('?-?(?<!\d)\d+)\/\s*('?\d+)(?:\D\s*('?-?\d+))?/, :ymd},
    {~r/('?-?(?<!\d)\d+)\.\s*('?\d+)\.\s*('?-?\d+)/, :ymd},
    {~r/\b(\d{2}|\d{4})?-?w(\d{2})(?:-?(\d))?\b/i, {:keys, ~w(cwyear cweek cwday)}},
    {~r/-w-(\d)\b/i, {:keys, ["cwday"]}},
    {~r/--(\d{2})?-(\d{2})\b/, {:keys, ~w(mon mday)}},
    {~r/--(\d{2})(\d{2})?\b/, {:keys, ~w(mon mday)}},
    {~r/(?<![,.])\b(\d{2}|\d{4})-(\d{3})\b/, {:keys, ~w(year yday)}},
    {~r/(?<!\d)\b-(\d{3})\b/, {:keys, ["yday"]}},
    {~r/'(\d+)\b/, {:keys, ["year"]}},
    {Regex.compile!("\\b(#{@mon})\\S*", "i"), :month},
    {~r/((?<!\d)\d+)(st|nd|rd|th)\b/i, :mday}
  ]

  def parse(text) when is_binary(text) do
    if byte_size(text) > 128, do: raise(ArgumentError, "string length exceeds the limit 128")
    text = Regex.replace(~r/[^-+',.\/:@[:alnum:]\[\]]+/, text, " ")

    {text, day} =
      remove(text, ~r/\b(sun|mon|tue|wed|thu|fri|sat)[^-\/\d\s]*/i, fn [day] ->
        %{"wday" => Enum.find_index(@days, &(&1 == String.downcase(day)))}
      end)

    {text, time} = remove(text, @time, &time_fields/1)
    {text, date} = date_fields(text)
    fields = day |> Map.merge(time) |> Map.merge(date) |> fragment(text)
    bc = fields["_bc"] || Regex.match?(~r/\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)/i, text)
    fields = fields |> Map.delete("_bc") |> bc(bc)

    if Map.has_key?(fields, "zone") && is_nil(fields["offset"]),
      do: Map.put(fields, "offset", DateOffsets.parse(fields["zone"])),
      else: fields
  end

  def parse(_text), do: raise(ArgumentError, "time must be a string")

  defp date_fields(text) do
    Enum.find_value(@date_patterns, fn {pattern, type} ->
      case Regex.run(pattern, text) do
        nil -> nil
        [whole | groups] -> {String.replace(text, whole, " ", global: false), date(type, groups)}
      end
    end) || DateCompact.parse(text) || {text, %{}}
  end

  defp date(:eu, groups) do
    [d, _number, m, era, y] = pad(groups, 5)
    DateOrder.fields(y, month(m), d, bc_era?(era))
  end

  defp date(:us, groups) do
    [m, d, era, y] = pad(groups, 4)
    DateOrder.fields(y, month(m), d, bc_era?(era))
  end

  defp date(:ymd, groups) do
    [y, m, d] = pad(groups, 3)
    DateOrder.fields(y, m, d)
  end

  defp date(:vms, [d, m, y]), do: DateOrder.fields(y, month(m), d)

  defp date(:vms_us, groups) do
    [m, d, y] = pad(groups, 3)
    DateOrder.fields(y, month(m), d)
  end

  defp date(:jis, [era, y, m, d]) do
    ep = %{"m" => 1867, "t" => 1911, "s" => 1925, "h" => 1988, "r" => 2018}[String.downcase(era)]
    %{"year" => int(y) + ep, "mon" => int(m), "mday" => int(d)}
  end

  defp date(:month, [month]), do: %{"mon" => month |> month() |> int()}
  defp date(:mday, [d, _suffix]), do: %{"mday" => int(d)}

  defp date({:keys, keys}, groups),
    do:
      Enum.zip(keys, pad(groups, length(keys)))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {key, int(value)} end)

  defp time_fields(groups) do
    [clock, zone] = pad(groups, 2)
    [h, m, s, fraction, meridiem] = @clock |> Regex.run(clock, capture: :all_but_first) |> pad(5)

    hour =
      if meridiem,
        do: rem(int(h), 12) + if(String.downcase(meridiem) == "p", do: 12, else: 0),
        else: int(h)

    fields =
      %{"hour" => hour}
      |> optional("min", m, &int/1)
      |> optional("sec", s, &int/1)
      |> optional("sec_fraction", fraction, &DateCompact.rational/1)

    if zone, do: Map.put(fields, "zone", zone), else: fields
  end

  defp fragment(fields, text) do
    case Regex.run(~r/\A\s*(\d{1,2})\s*\z/, text, capture: :all_but_first) do
      [number] ->
        n = int(number)

        cond do
          fields["hour"] && !fields["mday"] && n in 1..31 -> Map.put(fields, "mday", n)
          fields["mday"] && !fields["hour"] && n in 0..24 -> Map.put(fields, "hour", n)
          true -> fields
        end

      _ ->
        fields
    end
  end

  defp remove(text, regex, fun) do
    case Regex.run(regex, text) do
      [whole | groups] -> {String.replace(text, whole, " ", global: false), fun.(groups)}
      nil -> {text, %{}}
    end
  end

  defp optional(map, _key, nil, _fun), do: map
  defp optional(map, key, value, fun), do: Map.put(map, key, fun.(value))
  defp bc(fields, false), do: fields

  defp bc(fields, true),
    do:
      Enum.reduce(~w(year cwyear), fields, fn key, acc ->
        if Map.has_key?(acc, key), do: Map.update!(acc, key, &(1 - &1)), else: acc
      end)

  defp bc_era?(nil), do: false
  defp bc_era?(era), do: String.starts_with?(String.downcase(era), "b")

  defp month(text),
    do: Integer.to_string(Enum.find_index(@months, &(&1 == String.downcase(text))) + 1)

  defp pad(groups, n),
    do:
      Enum.map(
        groups ++ List.duplicate(nil, n - length(groups)),
        &if(&1 == "", do: nil, else: &1)
      )

  defp int(string), do: String.to_integer(string)
end
