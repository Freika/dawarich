defmodule Dawarich.ReleaseMigrations do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Unreleased

  @releases [Unreleased]

  def all, do: @releases

  def find(release), do: Enum.find(@releases, &(&1.release() == release))
end
