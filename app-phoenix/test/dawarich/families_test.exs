defmodule Dawarich.FamiliesTest do
  use Dawarich.ScratchCase,
    async: true,
    group: :scratch_case_db,
    tables: ~w(family_invitations family_location_requests),
    sequences: ~w(family_invitations family_location_requests)

  alias Dawarich.Families

  @now ~N[2026-09-26 12:00:00]

  setup_all do
    scratch_sql!("""
    CREATE TABLE family_invitations (
      id bigserial PRIMARY KEY, status integer NOT NULL DEFAULT 0,
      expires_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE TABLE family_location_requests (
      id bigserial PRIMARY KEY, status integer NOT NULL DEFAULT 0,
      expires_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    """)

    :ok
  end

  describe "expire_invitations/2" do
    test "expires pending invitations whose expiry is before now and keeps their updated_at" do
      insert("family_invitations", [
        {0, "2026-09-26 11:59:59.999999", "2026-09-20 10:00:00"},
        {0, "2026-09-26 12:00:00", "2026-09-20 10:00:00"},
        {0, "2026-09-27 12:00:00", "2026-09-20 10:00:00"}
      ])

      assert Families.expire_invitations(ScratchRepo, @now) == {1, 0}

      assert rows("family_invitations") == [
               {1, 2, ~N[2026-09-20 10:00:00.000000]},
               {2, 0, ~N[2026-09-20 10:00:00.000000]},
               {3, 0, ~N[2026-09-20 10:00:00.000000]}
             ]
    end

    test "never expires accepted, expired or cancelled invitations" do
      insert("family_invitations", [
        {1, "2026-09-25 12:00:00", "2026-09-20 10:00:00"},
        {2, "2026-09-25 12:00:00", "2026-09-20 10:00:00"},
        {3, "2026-09-25 12:00:00", "2026-09-20 10:00:00"}
      ])

      assert Families.expire_invitations(ScratchRepo, @now) == {0, 0}
      assert Enum.map(rows("family_invitations"), &elem(&1, 1)) == [1, 2, 3]
    end

    test "deletes expired and cancelled invitations last updated more than 30 days before now" do
      insert("family_invitations", [
        {2, "2026-08-01 00:00:00", "2026-08-27 11:59:59.999999"},
        {2, "2026-08-01 00:00:00", "2026-08-27 12:00:00"},
        {3, "2026-10-01 00:00:00", "2026-08-01 00:00:00"},
        {1, "2026-08-01 00:00:00", "2026-08-01 00:00:00"},
        {0, "2026-10-01 00:00:00", "2026-08-01 00:00:00"}
      ])

      assert Families.expire_invitations(ScratchRepo, @now) == {0, 2}
      assert Enum.map(rows("family_invitations"), &elem(&1, 0)) == [2, 4, 5]
    end

    test "expires and deletes a stale pending invitation in the same run" do
      insert("family_invitations", [{0, "2026-08-20 00:00:00", "2026-08-01 00:00:00"}])

      assert Families.expire_invitations(ScratchRepo, @now) == {1, 1}
      assert rows("family_invitations") == []
    end
  end

  describe "expire_location_requests/2" do
    test "expires pending requests whose expiry is at or before now and stamps updated_at" do
      insert("family_location_requests", [
        {0, "2026-09-26 12:00:00", "2026-09-25 10:00:00"},
        {0, "2026-09-26 12:00:00.000001", "2026-09-25 10:00:00"}
      ])

      assert Families.expire_location_requests(ScratchRepo, @now) == 1

      assert rows("family_location_requests") == [
               {1, 3, ~N[2026-09-26 12:00:00.000000]},
               {2, 0, ~N[2026-09-25 10:00:00.000000]}
             ]
    end

    test "leaves accepted, declined and expired requests alone" do
      insert("family_location_requests", [
        {1, "2026-09-25 12:00:00", "2026-09-25 10:00:00"},
        {2, "2026-09-25 12:00:00", "2026-09-25 10:00:00"},
        {3, "2026-09-25 12:00:00", "2026-09-25 10:00:00"}
      ])

      assert Families.expire_location_requests(ScratchRepo, @now) == 0

      assert rows("family_location_requests") ==
               for(
                 {id, status} <- [{1, 1}, {2, 2}, {3, 3}],
                 do: {id, status, ~N[2026-09-25 10:00:00.000000]}
               )
    end

    test "is idempotent" do
      insert("family_location_requests", [{0, "2026-09-26 11:00:00", "2026-09-25 10:00:00"}])

      assert Families.expire_location_requests(ScratchRepo, @now) == 1
      assert Families.expire_location_requests(ScratchRepo, @now) == 0
    end
  end

  defp insert(table, rows) do
    values =
      Enum.map_join(rows, ", ", fn {status, expires_at, updated_at} ->
        "(#{status}, '#{expires_at}', '#{updated_at}')"
      end)

    scratch_sql!("INSERT INTO #{table} (status, expires_at, updated_at) VALUES #{values}")
  end

  defp rows(table) do
    ScratchRepo.query!("SELECT id, status, updated_at FROM #{table} ORDER BY id", [], log: false).rows
    |> Enum.map(&List.to_tuple/1)
  end
end
