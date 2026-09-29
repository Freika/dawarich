defmodule Dawarich.RailsRoot do
  @moduledoc false

  def join(path), do: Path.join(Application.get_env(:dawarich, :rails_root) || File.cwd!(), path)
end
