defmodule Dawarich.Seeds.AssetsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Seeds.Countries

  test "seed asset resolves through application priv and matches repository source bytes" do
    source = Path.expand("../../../../lib/assets/countries.geojson.gz", __DIR__)
    asset = Countries.asset_path()
    assert asset == Application.app_dir(:dawarich, "priv/countries.geojson.gz")
    assert File.read!(asset) == File.read!(source)
    copied_priv = Path.join(System.tmp_dir!(), "a12h-priv-#{System.unique_integer([:positive])}")
    File.mkdir_p!(copied_priv)
    on_exit(fn -> File.rm_rf!(copied_priv) end)
    File.cp!(asset, Path.join(copied_priv, "countries.geojson.gz"))
    assert File.read!(Countries.asset_path(priv_dir: copied_priv)) == File.read!(source)
  end
end
