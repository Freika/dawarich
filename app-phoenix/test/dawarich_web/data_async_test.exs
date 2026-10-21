defmodule DawarichWeb.DataAsyncTest do
  use ExUnit.Case, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Accounts.Principal
  alias Dawarich.Test.NativeAdminUI
  alias DawarichWeb.DataAsync

  setup do
    %{target: user} = NativeAdminUI.setup!()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}},
      private: %{data_principal: Principal.scope(Scope.for_user(user, "en"))}
    }

    %{socket: socket}
  end

  test "an old timeout cannot stop a replacement read", %{socket: socket} do
    {old, socket} = DataAsync.register(socket, :details, "filter")
    {new, socket} = DataAsync.register(socket, :details, "filter")
    assert old != new
    assert {:stale, socket} = DataAsync.timeout(socket, old)
    assert DataAsync.active?(socket, new)
    assert {:error, :timeout, socket} = DataAsync.timeout(socket, new)
    refute DataAsync.active?(socket, new)
  end

  test "cancelled and stale read results cannot replace current data", %{socket: socket} do
    {old, socket} = DataAsync.register(socket, :details, "old")
    socket = DataAsync.advance(socket)
    {current, socket} = DataAsync.register(socket, :details, "new")
    assert {:stale, socket} = DataAsync.finish(socket, old, {:ok, :old})
    assert DataAsync.active?(socket, current)
    timer = DataAsync.timer(socket, current)
    assert {:ok, :new, socket} = DataAsync.finish(socket, current, {:ok, :new})
    refute DataAsync.active?(socket, current)
    assert Process.read_timer(timer) == false
  end

  test "async delivery refuses changed identity before projection", %{socket: socket} do
    {run, socket} = DataAsync.register(socket, :details, "filter")

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password = 'changed-00000000000000000000000' WHERE id = $1",
      [socket.private.data_principal.user.id],
      log: false
    )

    assert {:error, :stale_session, socket} = DataAsync.finish(socket, run, {:ok, :private_data})
    refute DataAsync.active?(socket, run)
  end
end
