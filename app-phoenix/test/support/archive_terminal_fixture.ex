defmodule Dawarich.Test.ArchiveTerminalFixture do
  import ExUnit.Assertions

  def acknowledge_children!(c, repo) do
    ids =
      repo.query!(
        "UPDATE imports SET status=2 WHERE id IN (SELECT child_id FROM phoenix.import_archive_children WHERE parent_id=$1 AND phase='queued') RETURNING id",
        [c.import.id],
        log: false
      ).rows
      |> List.flatten()

    assert ids != []

    children =
      Enum.map(c.expected["children"], fn child ->
        if child["id"] in ids, do: Map.put(child, "status", "completed"), else: child
      end)

    jobs = c.expected["jobs"]

    accepted =
      for id <- ids,
          not Enum.any?(jobs, &(&1["type"] == "Import::ProcessJob" and &1["args"] == [id])),
          do: %{"type" => "Import::ProcessJob", "args" => [id]}

    effects =
      c.expected["ordered_effects"] ++
        Enum.map(accepted, &%{"kind" => "rails.job", "payload" => &1})

    %{
      c
      | expected:
          c.expected
          |> Map.put("children", children)
          |> Map.put("jobs", jobs ++ accepted)
          |> Map.put("ordered_effects", effects)
    }
  end
end
