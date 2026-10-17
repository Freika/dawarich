defmodule DawarichWeb.ConnectedMountQueryBudgetTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  @user_row ~s|FROM "public"."users" AS u0 WHERE ((u0."id" = $1)|

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "mount-budget-#{id}@dawarich.test",
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

  for {path, limit} <- [
        {"/map?start_at=2026-06-01&end_at=2026-06-02", 2},
        {"/trips", 2},
        {"/insights?year=all", 4}
      ] do
    test "the connected mount of #{path} reads the user row at most #{limit} times before any write",
         %{id: id} do
      {view, queries} = connected(id, unquote(path))
      assert Process.alive?(view.pid)
      reads = Enum.take_while(queries, &(not (&1 =~ ~r/\A\s*(INSERT|UPDATE|DELETE)/)))
      assert Enum.count(reads, &String.contains?(&1, @user_row)) <= unquote(limit)
    end
  end

  test "the connected map mount loads the navbar once", %{id: id} do
    {_view, queries} = connected(id, "/map?start_at=2026-06-01&end_at=2026-06-02")
    assert Enum.count(queries, &String.contains?(&1, ~s|FROM "notifications" AS n0|)) == 1
  end

  test "the connected map mount loads posters and route videos once each", %{id: id} do
    {_view, queries} = connected(id, "/map?start_at=2026-06-01&end_at=2026-06-02")
    assert Enum.count(queries, &String.contains?(&1, ~s|FROM "posters" AS p0|)) == 1
    assert Enum.count(queries, &String.contains?(&1, ~s|FROM "route_videos" AS r0|)) == 1
  end

  test "a map event after the connected mount re-admits from the database", %{id: id} do
    {view, _} = connected(id, "/map?start_at=2026-06-01&end_at=2026-06-02")
    Repo.query!("UPDATE users SET encrypted_password = $2 WHERE id = $1", [id, "revoked"])
    render_patch(view, "/map?start_at=2026-06-02&end_at=2026-06-03")
    assert_redirect(view)
  end

  defp connected(id, path) do
    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get(path)
    key = {__MODULE__, make_ref()}
    owner = self()

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ -> send(owner, {key, self(), metadata.query}) end,
      nil
    )

    try do
      {:ok, view, _html} = live(conn)
      _ = render(view)
      {view, collect(key, view.pid, [])}
    after
      :telemetry.detach(key)
    end
  end

  defp collect(key, pid, acc) do
    receive do
      {^key, ^pid, query} -> collect(key, pid, [query | acc])
      {^key, _other, _query} -> collect(key, pid, acc)
    after
      0 -> Enum.reverse(acc)
    end
  end
end
