defmodule Dawarich.ReleaseMigrations do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.{Unreleased, V1_14_4, V1_15_0, V1_15_2}

  @releases [V1_14_4, V1_15_0, V1_15_2, Unreleased]

  def all, do: @releases

  def find(release), do: Enum.find(@releases, &(&1.release() == release))
end
