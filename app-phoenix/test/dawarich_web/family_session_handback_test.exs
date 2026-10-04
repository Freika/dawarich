defmodule DawarichWeb.FamilySessionHandbackTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]
  import Dawarich.Test.RawHTTP

  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    upstream = listen()
    saved = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, saved)
      :gen_tcp.close(upstream.listen)
    end)

    %{owner: owner, upstream: upstream}
  end

  @tag mutation: "family-session-writers"
  test "family documents invitations and JSON forward unsupported session writers before effects",
       c do
    for path <-
          ~w(/family /family/new /family/edit /family/invitations /family/location_requests/94001 /invitations/a9fpl-pending /family/invitations/a9fpl-pending /family/locations.json),
        {query, headers} <- [
          {"client=ios&locale=de", []},
          {"locale=de", [{"x-dawarich-client", "android"}]},
          {"client%5B%5D=ios", []},
          {"aff=synthetic-referral&locale=de", []},
          {"via=synthetic-referral", []}
        ] do
      conn = RailsUser.signed_in(c.owner.id, %{"locale" => "en"})

      conn =
        Enum.reduce(headers, conn, fn {key, value}, acc -> put_req_header(acc, key, value) end)

      forwarded(c, conn, path <> "?" <> query)
    end
  end

  @tag mutation: "family-json-locale"
  test "family JSON hands locale persistence to Rails before effects", c do
    forwarded(c, RailsUser.signed_in(c.owner.id), "/family/locations.json?locale=de")
  end

  defp forwarded(c, conn, path) do
    before = snapshot()
    response = Task.async(fn -> get(conn, path) end)
    socket = accept(c.upstream)
    {head, _rest} = read_head(socket)
    assert request_line(head) == "GET #{path} HTTP/1.1"

    for {key, value} <- conn.req_headers,
        key in ~w(cookie x-dawarich-client),
        do: assert(header(head, key) == [value])

    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    returned = Task.await(response)
    :gen_tcp.close(socket)
    assert returned.status == 200
    assert returned.resp_body == "rails"
    assert returned.resp_cookies == %{}
    assert get_resp_header(returned, "set-cookie") == []
    refute Map.has_key?(returned.private, :phoenix_router)
    refute Map.has_key?(returned.private, :dawarich_rails_session_changes)
    refute Map.has_key?(returned.assigns, :current_user)
    assert snapshot() == before
  end

  defp snapshot do
    for table <-
          ~w(users families family_memberships family_invitations family_location_requests job_outbox),
        into: %{},
        do:
          {table,
           Repo.query!("SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text").rows}
  end
end
