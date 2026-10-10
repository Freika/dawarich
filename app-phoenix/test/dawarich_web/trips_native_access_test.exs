defmodule DawarichWeb.TripsNativeAccessTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts.Scope
  alias Dawarich.Accounts.Principal
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{DataAsync, NativeDataAuth}
  alias DawarichWeb.TripsNative.Access

  test "Trips admission and async runs share the C1 principal and registry" do
    user = RailsUser.insert!(%{id: 19491, email: "trips-c1@example.invalid"})
    principal = Principal.scope(Scope.for_user(user, "en"))
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = Access.put_principal(socket, principal)
    assert socket.private[:data_principal] == principal
    assert {:ok, %{user: %{id: 19491}}} = NativeDataAuth.scope(socket)
    {old, socket} = Access.register(socket, :days, "old")
    assert DataAsync.active?(socket, old)
    socket = Access.advance(socket)
    {current, socket} = Access.register(socket, :days, "current")
    assert {:stale, socket} = Access.timeout(socket, old)
    assert DataAsync.active?(socket, current)
    assert {:ok, :ready, socket} = Access.finish(socket, current, {:ok, {:ok, :ready}})
    refute DataAsync.active?(socket, current)
    {timed, socket} = Access.register(socket, :days, "timeout")
    timer = DataAsync.timer(socket, timed)
    assert {:error, :timeout, socket} = Access.timeout(socket, timed)
    refute DataAsync.active?(socket, timed)
    assert Process.read_timer(timer) == false
  end
end
