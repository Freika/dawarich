defmodule Dawarich.ReleaseMigrations.Unreleased do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  @impl true
  def release, do: "unreleased"

  @impl true
  def steps, do: []

  @impl true
  def data_versions, do: []
end
