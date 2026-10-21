defmodule Dawarich.Imports.GooglePhone.Coordinates do
  @moduledoc false
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def parse(value) do
    unless Ruby.blank?(value) do
      parts =
        value
        |> Value.to_s()
        |> String.replace("geo:", "")
        |> String.replace("°", "")
        |> String.trim()
        |> String.split(~r/,\s*/)
        |> Enum.reverse()
        |> Enum.drop_while(&(&1 == ""))
        |> Enum.reverse()

      if length(parts) >= 2 do
        [lat, lon | rest] = parts
        {Value.to_f(lat), Value.to_f(lon), if(rest == [], do: nil, else: Value.to_f(hd(rest)))}
      end
    end
  end
end
