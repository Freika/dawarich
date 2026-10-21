defmodule Dawarich.Visits.NameKey do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @table Path.expand("../../../priv/ruby_downcase.json", __DIR__)
  @external_resource @table
  @mapping @table |> File.read!() |> Jason.decode!() |> Map.fetch!("mapping")

  def build(name) do
    for <<codepoint::utf8 <- Ruby.strip(name || "")>>, into: "" do
      Map.get(@mapping, Integer.to_string(codepoint), <<codepoint::utf8>>)
    end
  end
end
