defmodule Dawarich.Jobs.PosixZone do
  @moduledoc false

  @fixed ~r/\A([A-Za-z]{3,}|<[A-Za-z0-9+-]{3,}>)([+-]?)(\d{1,2})(?::(\d{2}))?(?::(\d{2}))?\z/

  def load!(zone) do
    case Regex.run(@fixed, zone, capture: :all_but_first) do
      [name, sign, hours | rest] ->
        [minutes, seconds] = (rest ++ ["", ""]) |> Enum.take(2) |> Enum.map(&number/1)
        hours = String.to_integer(hours)

        if hours > 24 or minutes > 59 or seconds > 59,
          do: raise(ArgumentError, "invalid time zone")

        offset = (hours * 3600 + minutes * 60 + seconds) * if(sign == "-", do: 1, else: -1)

        %{
          types: {{offset, false}},
          offsets: [offset],
          transitions: {},
          abbr: String.trim(name, "<>")
        }

      _ ->
        raise ArgumentError, "invalid time zone"
    end
  end

  defp number(""), do: 0
  defp number(text), do: String.to_integer(text)
end
