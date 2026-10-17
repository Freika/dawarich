defmodule Dawarich.Jobs.Wave2TablesTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  test "the migration creates notification_events, delivery_claims and export_claims in the phoenix schema" do
    for table <- ~w(notification_events delivery_claims export_claims) do
      assert [[true]] == rows("SELECT to_regclass($1) IS NOT NULL", ["phoenix." <> table])
    end
  end
end
