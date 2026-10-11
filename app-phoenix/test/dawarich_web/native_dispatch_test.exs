defmodule DawarichWeb.NativeDispatchTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    context = NativeAdminUI.setup!()
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    parent = self()

    start_supervised!(
      {Task,
       fn ->
         case :gen_tcp.accept(listener) do
           {:ok, socket} ->
             send(parent, :rails_contacted)
             :gen_tcp.recv(socket, 0, 1000)

             :gen_tcp.send(
               socket,
               "HTTP/1.1 599 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
             )

             :gen_tcp.close(socket)

           {:error, :closed} ->
             :ok
         end
       end}
    )

    previous_routes = Application.fetch_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, ["tags", "api"])
    previous = Application.fetch_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, port})
    System.put_env("DAWARICH_RAILS", "on")

    on_exit(fn ->
      case previous_routes do
        {:ok, value} -> Application.put_env(:dawarich, :rails_routes, value)
        :error -> Application.delete_env(:dawarich, :rails_routes)
      end

      :gen_tcp.close(listener)

      case previous do
        {:ok, value} -> Application.put_env(:dawarich, :rails_upstream, value)
        :error -> Application.delete_env(:dawarich, :rails_upstream)
      end
    end)

    context
  end

  test "native routes and refusals never contact a Rails upstream", %{actor: actor} do
    for {path, status} <- [
          {"/tags", 200},
          {"/tags.html", 200},
          {"/tags?format=turbo_stream", 406}
        ] do
      conn = NativeAdminUI.conn(actor) |> get(path)
      assert conn.status == status
      refute_received :rails_contacted
    end

    guest = build_conn() |> get("/tags")
    assert guest.status == 302
    refute_received :rails_contacted
  end

  test "unknown native routes return local 404 without fallback" do
    for path <- ~w(/missing-native-route /api/v1/missing-native-route /missing-native-account) do
      conn = build_conn() |> get(path)
      assert conn.status == 404
      refute_received :rails_contacted
    end
  end

  test "native route metadata contains only behavior contracts" do
    for route <- Phoenix.Router.routes(DawarichWeb.Router) do
      refute Map.has_key?(route.metadata, :rails_gate)
      refute Map.has_key?(route.metadata, :rails_key)
      refute Map.has_key?(route.metadata, :slice)
    end
  end
end
