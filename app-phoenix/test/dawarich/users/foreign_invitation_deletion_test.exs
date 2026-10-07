defmodule Dawarich.Users.ForeignInvitationDeletionTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, Jobs.Processed, Users.DestroyWorker}
  alias Dawarich.Test.RailsUser

  @tag :foreign_invitation_refusal
  test "account deletion refuses a foreign-sent family invitation and rolls back all effects" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

    owner =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "owner-#{Ecto.UUID.generate()}@example.invalid",
        deleted_at: NaiveDateTime.utc_now()
      })

    inviter =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "inviter-#{Ecto.UUID.generate()}@example.invalid"
      })

    args = %{"user_id" => owner.id, "event_id" => Ecto.UUID.generate()}

    try do
      [[family]] =
        query(
          "INSERT INTO families(creator_id,name,created_at,updated_at) VALUES($1,'Synthetic',now(),now()) RETURNING id",
          [owner.id]
        )

      [[membership]] =
        query(
          "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,0,now(),now()) RETURNING id",
          [family, owner.id]
        )

      [[invitation]] =
        query(
          "INSERT INTO family_invitations(family_id,invited_by_id,email,token,expires_at,created_at,updated_at) VALUES($1,$2,'synthetic@example.invalid',$3,now()+interval '1 day',now(),now()) RETURNING id",
          [family, inviter.id, Ecto.UUID.generate()]
        )

      [[sent]] =
        query(
          "INSERT INTO family_invitations(family_id,invited_by_id,email,token,expires_at,created_at,updated_at) VALUES($1,$2,'sent@example.invalid',$3,now()+interval '1 day',now(),now()) RETURNING id",
          [family, owner.id, Ecto.UUID.generate()]
        )

      [[import]] =
        query(
          "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES($1,'owned',now(),now()) RETURNING id",
          [owner.id]
        )

      [[point]] =
        query(
          "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1,ST_GeomFromText('POINT(0 0)',4326),now(),now()) RETURNING id",
          [owner.id, import]
        )

      refute Repo.in_transaction?()
      assert {:error, {:cleanup, :foreign_key_violation}} = DestroyWorker.run(Repo, args)
      refute Processed.done?(Repo, args["event_id"])

      for {table, id} <- [
            {"users", owner.id},
            {"users", inviter.id},
            {"families", family},
            {"family_memberships", membership},
            {"family_invitations", invitation},
            {"family_invitations", sent},
            {"imports", import},
            {"points", point}
          ] do
        assert query("SELECT id FROM #{table} WHERE id=$1", [id]) == [[id]]
      end

      assert query("SELECT count(*) FROM oban.oban_jobs WHERE args->>'user_id'=$1", [
               to_string(owner.id)
             ]) == [[0]]

      assert query("SELECT 1", []) == [[1]]
      query("DELETE FROM family_invitations WHERE id=$1", [invitation])
      assert :ok = DestroyWorker.run(Repo, args)
      assert Processed.done?(Repo, args["event_id"])
      assert query("SELECT id FROM family_invitations WHERE id=$1", [sent]) == []
      assert query("SELECT id FROM users WHERE id=$1", [inviter.id]) == [[inviter.id]]
    after
      query(
        "DELETE FROM family_invitations WHERE family_id IN(SELECT id FROM families WHERE creator_id=$1)",
        [owner.id]
      )

      query("DELETE FROM family_memberships WHERE user_id=$1", [owner.id])
      query("DELETE FROM families WHERE creator_id=$1", [owner.id])

      for table <- ~w(points imports),
          do: query("DELETE FROM #{table} WHERE user_id=$1", [owner.id])

      query("DELETE FROM oban.oban_jobs WHERE args->>'user_id'=$1", [to_string(owner.id)])

      query("DELETE FROM phoenix.processed_commands WHERE event_id=$1", [
        Ecto.UUID.dump!(args["event_id"])
      ])

      query("DELETE FROM users WHERE id=ANY($1::bigint[])", [[owner.id, inviter.id]])
    end
  end

  defp query(sql, params), do: Repo.query!(sql, params, log: false).rows
end
