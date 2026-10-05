defmodule Dawarich.AccountApi.ExistTest do
  use Dawarich.IngestCase
  alias Dawarich.AccountApi.Exist
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  @moduletag api_public_only: true
  @secret "a4rest-manager-synthetic"

  @tag :account_secret
  test "exist uses manager secret and fails closed when unconfigured" do
    assert {:ok, 503, _} = Exist.run(%{"ids" => []}, "", %{})
    assert {:ok, 401, _} = Exist.run(%{"ids" => []}, "wrong", env())
    assert {:ok, 200, _} = Exist.run(%{"ids" => []}, @secret, env())
  end

  @tag :account_deleted
  test "exist coerces unique integer ids and excludes deleted users" do
    one = user!()
    two = user!()
    deleted = user!(%{deleted_at: NaiveDateTime.utc_now()})
    ids = [two, one, deleted, one, nil, "bad", " #{one} ", "#{one}x", "9_999_999", true, 1.5]
    assert {:ok, 200, term} = Exist.run(%{"ids" => ids}, @secret, env())

    assert decode(term) == %{
             "existing" => [one, two],
             "missing" => [deleted, 9_999_999]
           }
  end

  @tag :account_order
  @tag mutation: "M-A2-order"
  test "exist returns ascending ids despite descending insertion and request order" do
    first = user!(%{id: 953_812})
    second = user!(%{id: 953_811})
    Repo.query!("SET LOCAL enable_indexscan=off")
    Repo.query!("SET LOCAL enable_bitmapscan=off")
    ids = [first, second]

    assert {:ok, 200, term} = Exist.run(%{"ids" => ids}, @secret, env())
    assert decode(term)["existing"] == [second, first]
  end

  defp env, do: %{"SUBSCRIPTION_WEBHOOK_SECRET" => @secret}
  defp decode(term), do: term |> Ruby.json() |> IO.iodata_to_binary() |> Jason.decode!()
end
