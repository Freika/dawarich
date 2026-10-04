defmodule Dawarich.Imports.Kml.TimeRange do
  @moduledoc false
  alias Dawarich.Imports.ImportTime
  alias Dawarich.Imports.Kml.Points

  def range(path, context) do
    timestamp =
      Enum.find_value(
        [{"TimeStamp", "when"}, {"TimeSpan", "begin"}, {"TimeSpan", "end"}],
        fn pair ->
          case Points.fields(path, fn nodes -> pair?(nodes, pair) end) |> Enum.take(1) do
            [] -> nil
            [value] -> {:found, value}
          end
        end
      )

    case timestamp do
      {:found, text} ->
        value = parse!(text, context)
        {value, value}

      nil ->
        named(path, context)
    end
  end

  def parse!(text, context) do
    now =
      case context.now do
        fun when is_function(fun, 0) -> fun.()
        now -> now
      end

    now = if match?(%NaiveDateTime{}, now), do: DateTime.from_naive!(now, "Etc/UTC"), else: now
    value = ImportTime.parse(text, context.zone, now, context.repo)
    if is_nil(value), do: raise(ArgumentError, "KML timestamp could not be parsed")
    value
  end

  def interpolate({first, _}, 1, 0), do: first

  def interpolate({first, last}, count, index),
    do: round(first + (last - first) / (count - 1) * index)

  defp named(path, context) do
    name =
      Points.fields(path, fn
        [{"name", _, _}, {"Placemark", _, _} | _] -> true
        _ -> false
      end)
      |> Enum.take(1)
      |> List.first()

    case name &&
           Regex.run(
             ~r/\A(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) - (\d{4}-\d{2}-\d{2} \d{2}:\d{2})\z/,
             String.trim(name)
           ) do
      [_, first, last] -> {parse!(first, context), parse!(last, context)}
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp pair?([{a, _, _}, {b, _, _} | _], {b, a}), do: true
  defp pair?(_, _), do: false
end
