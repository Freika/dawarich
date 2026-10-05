defmodule Dawarich.ProxyStackShutdownTest do
  use ExUnit.Case, async: false

  @tag :real_stand
  @tag skip: is_nil(System.get_env("RELEASE_SHUTDOWN_PORT"))
  test "stand shutdown returns only after its own epmd node is unregistered" do
    port = System.fetch_env!("RELEASE_SHUTDOWN_PORT")
    node = "dawarich_#{port}"
    {before, 0} = System.cmd("epmd", ["-names"])
    assert before =~ "name #{node} at"

    script = Path.expand("../../../app-phoenix/scripts/proxy_stack.sh", __DIR__)

    {output, result} =
      System.cmd("sh", [script, "--down"], env: [{"PORT", port}], stderr_to_stdout: true)

    assert result == 0, output

    {after_shutdown, 0} = System.cmd("epmd", ["-names"])
    refute after_shutdown =~ "name #{node} at"

    other_nodes = fn names ->
      Regex.scan(~r/^name (\S+) at/m, names, capture: :all_but_first)
      |> List.flatten()
      |> Enum.reject(&(&1 == node))
      |> Enum.sort()
    end

    assert other_nodes.(after_shutdown) == other_nodes.(before)
  end
end
