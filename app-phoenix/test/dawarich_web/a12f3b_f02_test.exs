defmodule DawarichWeb.A12f3bF02Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus
  alias Dawarich.{Families, Repo}
  setup do: seed()

  @tag a12f3b_case: "F02a"
  test "native F02a family create update validation and ownership preserve effects", c do
    assert {:error, %{errors: [_ | _]}} =
             Families.create(scope(c.outsider), %{"name" => ""}, opts())

    assert {:ok, family} =
             Families.create(scope(c.outsider), %{"name" => "  Native family  "}, opts())

    assert records(
             "SELECT f.id,f.name,m.role FROM families f JOIN family_memberships m ON m.family_id=f.id WHERE m.user_id=$1",
             [c.outsider.id]
           ) == [[family, "Native family", 0]]

    for name <- ~w(PATCH PUT POST) do
      assert {:ok, ^family} = Families.update(scope(c.outsider), %{"name" => name}, opts())
      assert records("SELECT name FROM families WHERE id=$1", [family]) == [[name]]
    end

    assert {:error, :stale_session} = Families.create(scope(nil), %{"name" => "guest"}, opts())

    assert {:error, :unauthorized} =
             Families.update(scope(c.member), %{"name" => "foreign"}, opts())

    assert records("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [c.outsider.id])
    Repo.query!("DELETE FROM families WHERE id=$1", [family])

    assert {:ok, _} =
             Families.WebCreate.run(
               Repo,
               c.outsider,
               %{"name" => "Notification refused"},
               %{now: ~U[2026-10-03 10:00:00Z], locale: "en", self_hosted: true},
               notify: fn -> raise "synthetic notification failure" end
             )
  end

  @tag a12f3b_case: "F02b"
  test "native F02b invalid update preserves original name and entered values", c do
    for value <- ["", String.duplicate("x", 51), String.duplicate("e\u0301", 26)] do
      assert {:error, %{errors: [_ | _], values: %{"name" => ^value}}} =
               Families.update(scope(c.owner), %{"name" => value}, opts())

      assert records("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]
    end

    assert {:ok, 91001} =
             Families.update(scope(c.owner), %{"name" => %{"nested" => "bad"}}, opts())

    assert {:error, :unauthorized} =
             Families.update(scope(c.outsider), %{"name" => "foreign"}, opts())

    assert records("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]
  end
end
