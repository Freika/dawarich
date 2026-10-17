defmodule Dawarich.RailsRoot do
  @moduledoc false

  @source_root Path.expand("../../..", __DIR__)

  def root,
    do: Application.get_env(:dawarich, :rails_root) || System.get_env("APP_PATH") || @source_root

  def join(path), do: Path.join(root(), path)
end
