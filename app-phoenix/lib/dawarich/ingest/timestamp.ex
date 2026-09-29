defmodule Dawarich.Ingest.Timestamp do
  @moduledoc false

  import Dawarich.Ingest.Ruby, only: [blank?: 1, to_s: 1, unsupported!: 1]

  defmodule Invalid do
    defexception message: "Timestamp must be a date and time or Unix seconds"
  end

  @range -2_147_483_648..2_147_483_647
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @days ~w(Mon Tue Wed Thu Fri Sat Sun)
  @iso ~r/\A(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?)?(?: ?(Z|[+-]\d{2}(?::?\d{2})?))?\z/
  @rfc ~r/\A(?:(Mon|Tue|Wed|Thu|Fri|Sat|Sun), )?(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) (GMT|UTC|UT|Z|[+-]\d{4})\z/

  def points(value) do
    if blank?(value), do: nil, else: value |> to_s() |> points_epoch() |> in_range!()
  end

  def traccar(value) do
    string = to_s(value)

    cond do
      string =~ ~r/\A\d+\z/ -> string |> String.to_integer() |> milliseconds()
      blank?(string) -> nil
      true -> datetime(string)
    end
  rescue
    Invalid -> nil
  end

  defp milliseconds(n) when n > 10_000_000_000, do: div(n, 1000)
  defp milliseconds(n), do: n

  defp points_epoch(string) do
    if string =~ ~r/\A-?\d+\z/, do: String.to_integer(string), else: datetime(string)
  end

  defp in_range!(epoch) when epoch in @range, do: epoch
  defp in_range!(_epoch), do: raise(Invalid)

  defp datetime(string) do
    cond do
      match = Regex.run(@iso, string, capture: :all_but_first) -> iso(pad(match, 7))
      match = Regex.run(@rfc, string, capture: :all_but_first) -> rfc(match)
      true -> unsupported!("timestamp outside the owned grammar")
    end
  end

  defp iso([y, mo, d, h, mi, s, zone]),
    do: epoch(int(y), int(mo), int(d), {int(h), int(mi), int(s)}, zone)

  defp rfc([day, d, mon, y, h, mi, s, zone]) do
    month = Enum.find_index(@months, &(&1 == mon)) + 1
    epoch = epoch(int(y), month, int(d), {int(h), int(mi), int(s)}, zone)

    if day != "" and
         Enum.at(@days, Date.day_of_week(Date.new!(int(y), month, int(d))) - 1) != day,
       do: unsupported!("weekday does not match the date"),
       else: epoch
  end

  defp epoch(y, mo, d, {h, mi, s}, zone) do
    case Date.new(y, mo, d) do
      {:ok, date} when h <= 23 and mi <= 59 and s <= 59 ->
        Date.diff(date, ~D[1970-01-01]) * 86_400 + h * 3_600 + mi * 60 + s - offset(zone)

      {:ok, _date} ->
        unsupported!("clock out of range")

      {:error, _} ->
        raise Invalid
    end
  end

  defp offset(zone) when zone in ["", "Z", "GMT", "UTC", "UT"], do: 0

  defp offset(<<sign, hours::binary-size(2), rest::binary>>) do
    {h, m} = {int(hours), int(String.trim_leading(rest, ":"))}
    if h > 14 or m > 59, do: unsupported!("offset out of range")
    if sign == ?-, do: -(h * 3_600 + m * 60), else: h * 3_600 + m * 60
  end

  defp int(""), do: 0
  defp int(text), do: String.to_integer(text)

  defp pad(groups, n), do: groups ++ List.duplicate("", n - length(groups))
end
