defmodule DawarichWeb.A12f3bReviewR5Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus

  setup do: seed()

  @tag a12f3b_review: "R5"
  test "native R5 existing owner and member blank creation refuse authorization before effects",
       c do
    for actor <- [c.owner, c.member] do
      assert {:error, :unauthorized} =
               Dawarich.Families.create(scope(actor), %{"name" => ""}, opts())

      assert records("SELECT count(*) FROM families") == [[1]]
      assert records("SELECT count(*) FROM family_memberships") == [[2]]
    end
  end
end
