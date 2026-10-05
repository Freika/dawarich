defmodule Dawarich.Places.NameBuilder do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def build(properties) do
    components =
      ~w(name street housenumber city state)
      |> Enum.map(fn key ->
        value = properties[key]
        text = if is_nil(value), do: "", else: value |> Ruby.to_s() |> Ruby.strip()
        if text != "" and String.downcase(text) not in ["yes", "no"], do: text
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if components != [], do: Enum.join(components, ", ")
  end
end
