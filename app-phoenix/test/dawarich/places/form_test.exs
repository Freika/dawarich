defmodule Dawarich.Places.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.{Places, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds, as: S

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{scope: Scope.for_user(S.user!(11821), "en")}
  end

  test "native Place validation retains submitted values and field errors without effects", ctx do
    params = %{
      "name" => " ",
      "latitude" => "51.12345678",
      "longitude" => "bad",
      "note" => "Draft"
    }

    changeset = apply(Places, :change, [ctx.scope, %{}, params])
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :name)
    assert Keyword.has_key?(changeset.errors, :longitude)
    assert changeset.params["latitude"] == "51.12345678"
    assert changeset.params["note"] == "Draft"

    for attrs <- [
          %{"name" => String.duplicate("語", 256)},
          %{"name" => []},
          %{"source" => %{}},
          %{"tag_ids" => %{}},
          %{"latitude" => %{}},
          %{}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = apply(Places, :create, [ctx.scope, attrs])
    end

    assert Repo.query!("SELECT id FROM places WHERE user_id=$1", [ctx.scope.user.id]).rows == []
  end
end
