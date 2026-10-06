defmodule DawarichWeb.A12f3aVClosureTest do
  use Dawarich.JobsCase
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Repo
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = System.get_env("SELF_HOSTED")
    on_exit(fn -> env("SELF_HOSTED", previous) end)
    :ok
  end

  @tag a12f3a_v01: true
  test "V01: visits legacy navigation matches current Rails contract without a native-owner Rails effect" do
    for mode <- ["true", "false", nil],
        method <- [:get, :head],
        status <- [nil, "", "suggested", "declined"] do
      env("SELF_HOSTED", mode)
      path = "/visits" <> if(is_nil(status), do: "", else: "?status=" <> status)
      conn = dispatch(build_conn(), @endpoint, method, path, nil)
      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               "http://www.example.com/map/v2?panel=timeline&date=today&status=" <>
                 (status || "confirmed")
             ]

      assert conn.resp_body == ""
      assert get_resp_header(conn, "set-cookie") == []
    end

    oracle = File.read!("test/fixtures/a8vv/visits/a12f3a-v01.json") |> Jason.decode!()
    assert oracle["status"] == 302
    assert oracle["location"] == "http://www.example.com/map/v2?panel=timeline&date=today&status="
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  defp env(key, nil), do: System.delete_env(key)
  defp env(key, value), do: System.put_env(key, value)
end
