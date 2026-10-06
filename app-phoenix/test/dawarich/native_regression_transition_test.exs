defmodule Dawarich.NativeRegressionTransitionTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn

  setup do
    names =
      ~w(DAWARICH_RAILS SELF_HOSTED DAWARICH_PHOENIX_AUTH DAWARICH_RAILS_ROUTES DAWARICH_RAILS_SLICES FORCE_SSL)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    config = Application.get_all_env(:dawarich)
    Enum.each(names, &System.delete_env/1)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")
    Application.put_env(:dawarich, :phoenix_auth, [])
    Application.put_env(:dawarich, :rails_routes, [])
    {:ok, upstream} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, port})

    on_exit(fn ->
      :gen_tcp.close(upstream)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end

      for {key, value} <- config, do: Application.put_env(:dawarich, key, value)
    end)

    Dawarich.State.put_registration_enabled(Repo, false)
    %{upstream: upstream}
  end

  @tag :a12f4_a25_1
  test "standalone regression transition retains response and effect assertions without per-flow opt ins",
       ctx do
    sign_in = request(:get, "/users/sign_in")
    assert sign_in.status == 200
    assert sign_in.resp_body =~ ~s(action="/users/sign_in")
    assert get_resp_header(sign_in, "content-type") == ["text/html; charset=utf-8"]

    missing = request(:head, "/missing-native-runtime")
    assert missing.status == 404
    assert missing.resp_body == ""
    assert missing.halted

    key = "synthetic-native-runtime-note"
    actor = user!(%{api_key: key, settings: %{"timezone" => "UTC"}})

    created =
      request(
        :post,
        "/api/v1/notes",
        %{"note" => %{"body" => "Synthetic runtime note", "noted_at" => "2026-10-06T12:00:00Z"}},
        key
      )

    assert created.status == 201
    id = Jason.decode!(created.resp_body)["id"]

    assert rows("SELECT user_id, body FROM notes WHERE id=$1", [id]) == [
             [actor, "Synthetic runtime note"]
           ]

    before = rows("SELECT row_to_json(n)::text FROM notes n ORDER BY id")
    empty = request(:post, "/api/v1/notes", %{"note" => %{}}, key)
    assert empty.status == 400
    assert empty.halted

    assert Jason.decode!(empty.resp_body)["error"] ==
             "param is missing or the value is empty: note"

    assert rows("SELECT row_to_json(n)::text FROM notes n ORDER BY id") == before
    rejected = request(:post, "/api/v1/notes", %{"note" => %{"body" => ""}}, key)
    assert rejected.status == 422
    assert rejected.halted
    assert rows("SELECT row_to_json(n)::text FROM notes n ORDER BY id") == before
    fetched = request(:get, "/api/v1/notes/#{id}", nil, key)
    assert fetched.status == 200
    assert Jason.decode!(fetched.resp_body)["body"] == "Synthetic runtime note"
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream, 0)
  end

  defp request(method, path, body \\ nil, key \\ nil) do
    encoded = if body, do: Jason.encode!(body), else: ""
    conn = Plug.Test.conn(method, path, encoded)
    conn = if key, do: put_req_header(conn, "authorization", "Bearer " <> key), else: conn
    conn = if body, do: put_req_header(conn, "content-type", "application/json"), else: conn
    conn = put_req_header(conn, "content-length", Integer.to_string(byte_size(encoded)))
    conn = if key, do: put_req_header(conn, "accept", "application/json"), else: conn
    DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
  end
end
