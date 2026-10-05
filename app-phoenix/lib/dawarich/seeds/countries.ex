defmodule Dawarich.Seeds.Countries do
  @moduledoc false

  def asset_path(opts \\ []) do
    priv = Keyword.get_lazy(opts, :priv_dir, fn -> Application.app_dir(:dawarich, "priv") end)
    Path.join(priv, "countries.geojson.gz")
  end
end
