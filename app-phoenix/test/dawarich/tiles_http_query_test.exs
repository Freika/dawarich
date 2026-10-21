defmodule Dawarich.TilesHttpQueryTest do
  use Dawarich.DataCase, async: true

  test "tile statements run without JIT under the configured statement timeout" do
    assert Dawarich.Tiles.Http.query(
             "SELECT current_setting('jit'), current_setting('statement_timeout')",
             []
           ) == [["off", "5s"]]
  end
end
