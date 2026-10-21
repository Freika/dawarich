defmodule Dawarich.ReleaseMigrations.V1_15_4 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration
  alias Dawarich.ReleaseMigrations.Effects
  def release, do: "1.15.4"
  def data_versions, do: []

  def steps do
    [
      {"20261010120000", fn _repo -> :ok end},
      {"20261013120000", &Effects.ReloadBundledCountryBoundaries.run/1, transaction: false}
    ]
  end
end
