defmodule Dawarich.JobsCaseResetTest do
  use ExUnit.Case, async: false
  alias Dawarich.{JobsCase, ScratchRepo}

  test "scratch resets clear polymorphic rich text before record IDs are reused" do
    JobsCase.reset!(ScratchRepo)
    name = "reset-" <> Ecto.UUID.generate()

    on_exit(fn ->
      ScratchRepo.query!("DELETE FROM action_text_rich_texts WHERE name=$1", [name], log: false)
    end)

    ScratchRepo.query!(
      "INSERT INTO action_text_rich_texts(record_type,record_id,name,body,created_at,updated_at) VALUES('Trip',-1,$1,'<div>Synthetic</div>',now(),now())",
      [name],
      log: false
    )

    JobsCase.reset!(ScratchRepo)

    assert ScratchRepo.query!(
             "SELECT count(*) FROM action_text_rich_texts WHERE name=$1",
             [name],
             log: false
           ).rows == [[0]]
  end
end
