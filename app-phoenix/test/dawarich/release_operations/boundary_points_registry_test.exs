defmodule Dawarich.ReleaseOperations.BoundaryPointsRegistryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry
  alias Dawarich.ReleaseOperations.BoundaryPoints

  test "the boundary point reassignment resumes through the shared job registry" do
    for {path, row} <- [
          {"../docs/phoenix/fixed-rails-bugs.md", "FRB-S1160-BOUNDARY-FOLLOWUPS"},
          {"parity/expected_diffs.md", "ED-S1160-BOUNDARY-FOLLOWUPS"}
        ] do
      assert File.read!(path) =~ row
    end

    assert Registry.command(BoundaryPoints.command_type()) == {:ok, BoundaryPoints}
  end
end
