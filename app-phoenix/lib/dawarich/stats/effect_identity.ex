defmodule Dawarich.Stats.EffectIdentity do
  @moduledoc false

  def id(source, effect, args) do
    name = Jason.encode!([source, effect, args["user_id"], args["year"], args["month"]])
    Dawarich.Users.RecalculationPeriod.command_id(name)
  end
end
