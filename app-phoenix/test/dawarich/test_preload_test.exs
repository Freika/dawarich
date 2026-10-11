defmodule Dawarich.TestPreloadTest do
  use ExUnit.Case, async: true

  alias Dawarich.Test.Preload

  test "the suite boots with the application's runtime modules already loaded" do
    modules = Preload.modules()

    assert Application.spec(:dawarich, :modules) -- modules == []
    assert Phoenix.LiveView.Static in modules
    assert ExUnit.Assertions in modules
    refute Mix.Task in modules
    assert Enum.reject(modules, &:erlang.module_loaded/1) == []
  end
end
