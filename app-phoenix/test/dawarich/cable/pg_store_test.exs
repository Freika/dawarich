defmodule Dawarich.Cable.PgStoreTest do
  use Dawarich.JobsCase, async: false

  test "Cable schema is isolated and rejects invalid sequence and retirement bounds" do
    for table <- ~w(cable_streams cable_events) do
      assert rows("SELECT to_regclass($1)::text", ["phoenix." <> table]) == [
               ["phoenix." <> table]
             ]

      assert rows("SELECT to_regclass($1)::text", ["public." <> table]) == [[nil]]
    end

    assert rows("SELECT * FROM phoenix.cable_streams") == []
    rows("INSERT INTO phoenix.cable_streams(namespace, last_seq) VALUES ('schema', 2)")

    for {sql, code} <- [
          {"INSERT INTO phoenix.cable_streams(namespace) VALUES ('schema')", :unique_violation},
          {"UPDATE phoenix.cable_streams SET retired_through = 3", :check_violation},
          {"UPDATE phoenix.cable_streams SET retired_through = -1", :check_violation},
          {"UPDATE phoenix.cable_streams SET last_seq = -1", :check_violation},
          {"INSERT INTO phoenix.cable_events(namespace, seq, channel, payload, created_at) VALUES ('missing', 1, 'points', ''::bytea, now())",
           :foreign_key_violation},
          {"INSERT INTO phoenix.cable_events(namespace, seq, channel, payload, created_at) VALUES ('schema', 0, 'points', ''::bytea, now())",
           :check_violation}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: ^code}}} =
               ScratchRepo.query(sql, [], log: false)
    end

    rows(
      "INSERT INTO phoenix.cable_events(namespace, seq, channel, payload, created_at) VALUES ('schema', 1, 'points', ''::bytea, now())"
    )

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             ScratchRepo.query(
               "INSERT INTO phoenix.cable_events(namespace, seq, channel, payload, created_at) VALUES ('schema', 1, 'points', ''::bytea, now())",
               [],
               log: false
             )

    reset!(ScratchRepo)
    assert rows("SELECT * FROM phoenix.cable_streams") == []
    assert rows("SELECT * FROM phoenix.cable_events") == []
  end
end
