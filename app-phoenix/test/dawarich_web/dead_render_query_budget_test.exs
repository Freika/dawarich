defmodule DawarichWeb.DeadRenderQueryBudgetTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  @user_row ~s|FROM "public"."users" AS u0 WHERE ((u0."id" = $1)|

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "query-budget-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Budget trip",
      path: [[13, 52], [14, 53]],
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  for path <- ["/map?start_at=2026-06-01&end_at=2026-06-02", "/trips"] do
    test "a warm dead render of #{path} does not rescan the timezone catalogue", %{id: id} do
      queries = warm_render(id, unquote(path))
      assert Enum.filter(queries, &String.contains?(&1, "pg_timezone_names")) == []
    end
  end

  for path <- ["/map?start_at=2026-06-01&end_at=2026-06-02", "/trips"] do
    test "a dead render of #{path} reads the signed-in user row once", %{id: id} do
      queries = warm_render(id, unquote(path))
      assert Enum.count(queries, &String.contains?(&1, @user_row)) == 1
    end
  end

  test "a dead render of insights rereads the user row only after its refresh claim write", %{
    id: id
  } do
    queries = warm_render(id, "/insights?year=all")
    {before, rest} = Enum.split_while(queries, &(not String.starts_with?(&1, "INSERT")))
    assert Enum.count(before, &String.contains?(&1, @user_row)) == 1
    assert Enum.count(rest, &String.contains?(&1, @user_row)) == 1
  end

  test "a map dead render reads the settings column only with the users row", %{id: id} do
    queries = warm_render(id, "/map?start_at=2026-06-01&end_at=2026-06-02")
    assert Enum.filter(queries, &(&1 =~ ~r/SELECT settings FROM users/)) == []
  end

  test "a native points API request reads the API user's settings once", %{id: id} do
    Repo.query!("UPDATE users SET api_key = $2 WHERE id = $1", [id, "budget-key-#{id}"])

    path =
      "/api/v1/points?start_at=1780000000&end_at=1790000000&per_page=10&api_key=budget-key-#{id}"

    queries = warm_get(path)
    assert Enum.filter(queries, &(&1 =~ ~r/SELECT settings FROM users/)) == []
  end

  test "an admission after a user write in the same request reads the row again", %{id: id} do
    Dawarich.Accounts.DataAccess.with_request_memo(fn ->
      scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(id), "en")
      assert {:ok, _} = Dawarich.Accounts.DataAccess.admit(scope)
      Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [id])
      assert {:ok, admitted} = Dawarich.Accounts.DataAccess.admit(scope)
      assert admitted.user.status == 0
    end)
  end

  test "a finished request leaves no admission memo in its process", %{id: id} do
    assert RailsUser.signed_in(id) |> get("/trips") |> html_response(200)
    scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(id), "en")

    Task.async(fn -> Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [id]) end)
    |> Task.await()

    assert {:ok, admitted} = Dawarich.Accounts.DataAccess.admit(scope)
    assert admitted.user.status == 0
  end

  defp warm_get(path) do
    assert Phoenix.ConnTest.build_conn() |> get(path) |> response(200)
    owner = self()
    key = {__MODULE__, make_ref()}

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ -> if self() == owner, do: send(owner, {key, metadata.query}) end,
      nil
    )

    try do
      assert Phoenix.ConnTest.build_conn() |> get(path) |> response(200)
      collect(key, [])
    after
      :telemetry.detach(key)
    end
  end

  defp warm_render(id, path) do
    assert RailsUser.signed_in(id) |> get(path) |> html_response(200)
    owner = self()
    key = {__MODULE__, make_ref()}

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ -> if self() == owner, do: send(owner, {key, metadata.query}) end,
      nil
    )

    try do
      assert RailsUser.signed_in(id) |> get(path) |> html_response(200)
      collect(key, [])
    after
      :telemetry.detach(key)
    end
  end

  defp collect(key, acc) do
    receive do
      {^key, query} -> collect(key, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
