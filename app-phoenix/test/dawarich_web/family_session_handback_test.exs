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
    Code.ensure_loaded!(Dawarich.Accounts.User)
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
  test "independent JSON clients forward unsupported session writers before effects",
       c do
    for path <-
          ~w(/family/locations.json),
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

  test "native invitation landings handle legacy client hints locally without upstream replay",
       c do
    for path <- ~w(/invitations/a9fpl-pending /family/invitations/a9fpl-pending),
        {query, headers} <- [
          {"client=ios&locale=de", []},
          {"locale=de", [{"x-dawarich-client", "android"}]},
          {"client%5B%5D=ios", []},
          {"aff=synthetic-referral&locale=de", []},
          {"via=synthetic-referral", []}
        ] do
      before = snapshot()

      probe =
        Task.async(fn ->
          case :gen_tcp.accept(c.upstream.listen, 100) do
            {:ok, socket} ->
              read_head(socket)
              reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
              :gen_tcp.close(socket)
              :upstream

            {:error, :timeout} ->
              :native
          end
        end)

      conn =
        Enum.reduce(headers, RailsUser.signed_in(c.owner.id), fn {key, value}, acc ->
          put_req_header(acc, key, value)
        end)

      response = get(conn, path <> "?" <> query)
      result = Task.await(probe)
      assert response.status in [200, 302, 422]
      if response.status == 200, do: assert(response.resp_body =~ "/native/app")
      if response.status == 422, do: assert(response.resp_body =~ "422")

      if response.status == 302,
        do: assert(get_resp_header(response, "location") == ["http://www.example.com/"])

      assert result == :native
      after_read = snapshot()

      expected =
        if String.contains?(query, "locale=de") and response.status != 422 do
          users =
            Enum.map(before["users"], fn [row] ->
              if row["id"] == c.owner.id do
                [current] = Enum.find(after_read["users"], fn [u] -> u["id"] == c.owner.id end)

                [
                  row
                  |> Map.update!("settings", &Map.put(&1, "locale", "de"))
                  |> Map.put("updated_at", current["updated_at"])
                ]
              else
                [row]
              end
            end)

          Map.put(before, "users", users)
        else
          before
        end

      same = after_read == expected

      changed =
        for {table, rows} <- expected, rows != after_read[table], into: %{} do
          fields =
            Enum.zip(rows, after_read[table])
            |> Enum.flat_map(fn {[a], [b]} ->
              for {key, value} <- a, value != b[key], do: key
            end)

          {table, Enum.uniq(fields)}
        end

      assert same, "Changed fields: #{inspect(changed)}"
    end
  end

  test "native family documents ignore legacy client hints without writes", c do
    for path <-
          ~w(/family /family/new /family/edit /family/invitations /family/location_requests/94001),
        query <- ~w(client=ios client%5B%5D=ios aff=synthetic-referral via=synthetic-referral) do
      before = snapshot()
      conn = get(RailsUser.signed_in(c.owner.id), path <> "?" <> query)
      assert conn.status in [200, 302]
      if conn.status == 200, do: assert(String.contains?(conn.resp_body, "/native/app"))
      assert snapshot() == before
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
