defmodule Dawarich.ReleaseOperations.BoundaryPointsRegistryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry
  alias Dawarich.ReleaseOperations.BoundaryPoints

  test "the boundary point reassignment resumes through the shared job registry" do
    assert Registry.command(BoundaryPoints.command_type()) == {:ok, BoundaryPoints}
  end
end
