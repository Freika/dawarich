defmodule Dawarich.TimeZoneOptions do
  @moduledoc false

  @source Path.expand("../../priv/time_zones.json", __DIR__)
  @external_resource @source
  @options for [label, iana] <-
                 @source |> File.read!() |> Jason.decode!() |> Map.fetch!("options"),
               do: {label, iana}

  def list, do: :persistent_term.get(__MODULE__, @options)
end
