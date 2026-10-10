defmodule DawarichWeb.TripsNative.Access do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.NativeM5.Dependencies
  alias DawarichWeb.{DataAsync, NativeDataAuth}

  defdelegate on_mount(mode, params, session, socket), to: NativeDataAuth
  defdelegate scope(socket), to: NativeDataAuth
  defdelegate principal(scope), to: Dependencies
  defdelegate admit(principal), to: DataAccess
  defdelegate advance(socket), to: DataAsync
  defdelegate register(socket, kind, fingerprint), to: DataAsync
  defdelegate start(socket, kind, fingerprint, inputs, reader), to: DataAsync
  defdelegate active?(socket, run), to: DataAsync
  defdelegate finish(socket, run, result), to: DataAsync
  defdelegate cancel_all(socket), to: DataAsync

  def put_principal(socket, principal),
    do: %{socket | private: Map.put(socket.private, :data_principal, principal)}

  def refuse(socket), do: NativeDataAuth.refuse(socket, :stale_session)

  def timeout(socket, run) do
    socket =
      if DataAsync.active?(socket, run),
        do: Phoenix.LiveView.cancel_async(socket, run),
        else: socket

    DataAsync.timeout(socket, run)
  end
end
