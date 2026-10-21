defmodule Dawarich.Jobs do
  @moduledoc false

  def repo, do: Application.get_env(:dawarich, :jobs_repo, Dawarich.Repo)
end
