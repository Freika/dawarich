defmodule DawarichWeb.A12f3bP01Test do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Posters.Persistence
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.{PostersController, PostersGate, RailsAuth, RailsCsrf}

  @tag a12f3b_case: "P01a"
  test "poster forms own all source create and delete outcomes" do
    id = Dawarich.Test.FrameSeeds.user!(97111, %{"locale" => "en", "timezone" => "UTC"}).id
    session = RailsUser.session(id)
    foreign = user!()
    {:ok, other} = Persistence.create(%{}, %{id: foreign}, "en")
    saved = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if saved, do: System.put_env("SELF_HOSTED", saved), else: System.delete_env("SELF_HOSTED")
    end)

    System.put_env("SELF_HOSTED", "false")

    for {accept, status} <- [
          {"text/html", 302},
          {"text/vnd.turbo-stream.html", 200},
          {"application/json", 406}
        ] do
      conn =
        request(
          session,
          :post,
          "/posters",
          %{
            "poster" => %{
              "name" => "Residual",
              "theme" => "missing",
              "distance" => "bad",
              "title" => %{"nested" => "ignored"}
            }
          },
          accept
        )

      assert conn.status == status

      assert [[poster, settings]] =
               Repo.query!(
                 "SELECT id,settings FROM posters WHERE user_id=$1 ORDER BY id DESC LIMIT 1",
                 [id]
               ).rows

      assert settings == %{"theme" => "missing", "distance" => "bad"}

      if status == 302 do
        assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]

        assert RailsFormRequests.rails_session(conn)["flash"]["flashes"]["notice"] =~
                 "generation started"
      end

      destroyed =
        request(session, :delete, "/posters/#{poster}tail", %{}, accept, "#{poster}tail")

      assert destroyed.status ==
               if(accept == "application/json",
                 do: 406,
                 else: if(accept == "text/html", do: 303, else: 200)
               )

      assert Repo.query!("SELECT id FROM posters WHERE id=$1", [poster]).rows == []

      assert request(session, :delete, "/posters/#{poster}", %{}, accept, to_string(poster)).status ==
               404
    end

    assert request(session, :delete, "/posters/#{other}", %{}, "text/html", to_string(other)).status ==
             404

    assert Repo.query!("SELECT id FROM posters WHERE id=$1", [other]).rows == [[other]]

    assert request(session, :delete, "/posters/missing", %{}, "text/html", "missing").status ==
             404

    assert request(session, :post, "/posters", %{"poster" => "scalar"}, "text/html").status == 422
    guest = request(%{}, :post, "/posters", %{"poster" => %{"name" => "Guest"}}, "text/html")
    assert guest.status == 302
    assert get_resp_header(guest, "location") == ["http://www.example.com/users/sign_in"]
  end

  @tag a12f3b_case: "P01b"
  test "poster failed create leaves no row or generation command" do
    id = user!()

    assert {:ok, poster} =
             Persistence.create(
               %{"name" => %{"nested" => "filtered"}, "theme" => %{}},
               %{id: id},
               "en"
             )

    assert Repo.query!("SELECT name,settings FROM posters WHERE id=$1", [poster]).rows == [
             ["Untitled poster", %{}]
           ]

    Dawarich.Jobs.Ownership.put!(Repo, "command:posters.create", :oban)
    Repo.query!("DROP TABLE public.job_outbox")
    assert {:error, _} = Persistence.create(%{"name" => "Atomic"}, %{id: id}, "en")
    assert Repo.query!("SELECT id FROM posters WHERE user_id=$1", [id]).rows == [[poster]]
    assert length(commands()) == 1
  end

  defp request(session, verb, path, params, accept, route_id \\ nil) do
    params = Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))
    body = Jason.encode!(params)

    conn =
      build_conn(verb, path, body)
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("accept", accept)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> assign(:api_tag, "form")
      |> DawarichWeb.Api.Body.call([])
      |> RailsAuth.call([])

    conn = %{conn | path_params: if(route_id, do: %{"id" => route_id}, else: %{})}
    assert PostersGate.native?(conn, conn.path_params)
    conn = PostersGate.call(conn, [])

    if conn.halted,
      do: conn,
      else: PostersController.call(conn, if(verb == :post, do: :create, else: :destroy))
  end
end
