defmodule DawarichWeb.TripFormsActionsTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  require Phoenix.LiveViewTest
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{RailsUser, TripsSeeds, ParityHTML}
  alias Dawarich.Trips.WebForm
  alias DawarichWeb.{TripForm, RailsCsrf}

  @effects File.read!("test/fixtures/trips/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses File.read!("test/fixtures/trips/remaining/responses.json")
             |> Jason.decode!()
             |> Map.fetch!("responses")

  defp seed(name) do
    entry = Enum.find(@effects, &(&1["name"] == name))
    actor = entry["before"]["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-form-#{actor["id"]}@example.invalid",
      api_key: "a8r-k-#{actor["id"]}",
      settings: actor["settings"],
      active_until: ~N[3026-10-03 11:00:00]
    })

    for row <- entry["before"]["trips"] do
      if row["user_id"] != actor["id"],
        do:
          RailsUser.insert!(%{
            id: row["user_id"],
            email: "foreign-#{row["user_id"]}@example.invalid"
          })

      TripsSeeds.trip!(%{
        id: row["id"],
        user_id: row["user_id"],
        name: row["name"],
        demo: row["demo"],
        started_at: naive(row["started_at"]),
        ended_at: naive(row["ended_at"]),
        path: row["path"]
      })
    end

    for rich <- entry["before"]["action_text_rich_texts"] do
      Repo.insert_all("action_text_rich_texts", [
        %{
          id: rich["id"],
          record_type: "Trip",
          record_id: rich["record_id"],
          name: "description",
          body: rich["body"],
          created_at: naive(rich["created_at"]),
          updated_at: naive(rich["updated_at"])
        }
      ])
    end

    Ownership.put!(
      Repo,
      "command:trips.calculate",
      String.to_existing_atom(entry["request"]["owner"])
    )

    session = RailsUser.session(actor["id"])

    %{
      entry: entry,
      user: Dawarich.Accounts.get(actor["id"]),
      session: session,
      token: RailsCsrf.masked_token(session)
    }
  end

  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()
  defp response(name), do: Enum.find(@responses, &(&1["name"] == name))

  defp page(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(".mx-auto.my-5") |> LazyHTML.to_html()

  defp submit(ctx, accept \\ "text/html") do
    req = ctx.entry["request"]
    params = Map.put(req["params"], "authenticity_token", ctx.token)

    params =
      if req["method"] == "POST",
        do: params,
        else: Map.put(params, "_method", String.downcase(req["method"]))

    post_form(ctx.session, Plug.Conn.Query.encode(params), [{"accept", accept}], req["path"])
  end

  test "forms and CRUD preserve Rails status markup and active gate" do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)

    for name <- ~w(new edit) do
      ctx = seed(name)
      id = ctx.entry["before"]["trips"] |> List.first() |> then(&(&1 && &1["id"]))
      assert {:ok, form} = WebForm.load(Repo, ctx.user, id, %{locale: "en"})

      html =
        Phoenix.LiveViewTest.render_component(&TripForm.page/1, %{
          form: form,
          locale: "en",
          csrf: "CSRF",
          base_url: "http://www.example.com"
        })

      golden = File.read!("test/fixtures/trips/remaining/pages/#{name}.html")
      assert ParityHTML.normalize(page(html)) == ParityHTML.normalize(page(golden))
      assert ParityHTML.stimulus(html) == ParityHTML.stimulus(page(golden))

      for selector <- ~w(trix-editor input[type=submit]) do
        assert functional(html, selector) == functional(golden, selector)
      end

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
        |> Phoenix.ConnTest.dispatch(
          DawarichWeb.Endpoint,
          :get,
          ctx.entry["request"]["path"],
          nil
        )

      assert conn.status == 200
      assert conn.resp_body =~ "trip_description"
      assert conn.resp_body =~ "import &quot;trix&quot;" or conn.resp_body =~ "import \"trix\""
    end

    for name <-
          ~w(create_oban update_name_ordinary_oban update_name_demo_sidekiq update_embedded_ordinary_oban destroy_ordinary_oban) do
      ctx = seed(name)
      conn = submit(ctx)
      expected = response(name)
      assert conn.status == expected["status"], name

      if name == "create_oban" do
        assert [location] = get_resp_header(conn, "location")
        assert location =~ ~r|http://www.example.com/trips/\d+$|
      else
        assert get_resp_header(conn, "location") == [expected["location"]]
      end

      assert rails_session(conn)["flash"]["flashes"] == expected["flash"]
    end

    for name <-
          ~w(create_blank_oban create_equal_oban create_bad_date_oban update_invalid_oban update_equal_oban) do
      ctx = seed(name)
      conn = submit(ctx)
      assert conn.status == 422, name
      actual = ParityHTML.normalize(page(conn.resp_body))

      expected =
        ParityHTML.normalize(page(File.read!("test/fixtures/trips/remaining/pages/#{name}.html")))

      assert actual == expected, name <> ": " <> ParityHTML.first_difference(actual, expected)
    end

    upstream = upstream!()

    for {name, accept} <- [
          {"create_sidekiq", "text/html"},
          {"update_date_ordinary_sidekiq", "text/html"}
        ] do
      ctx = seed(name)

      before =
        Repo.query!("SELECT (SELECT count(*) FROM trips), (SELECT count(*) FROM job_outbox)").rows

      {{line, body}, conn} = forwarded(upstream, fn -> submit(ctx, accept) end)
      assert conn.status == 204
      assert line =~ "POST #{ctx.entry["request"]["path"]} HTTP/1.1"
      assert body =~ "authenticity_token="
      expected = Map.put(ctx.entry["request"]["params"], "authenticity_token", ctx.token)

      expected =
        if ctx.entry["request"]["method"] == "POST",
          do: expected,
          else: Map.put(expected, "_method", "patch")

      assert body == Plug.Conn.Query.encode(expected)

      assert Repo.query!("SELECT (SELECT count(*) FROM trips), (SELECT count(*) FROM job_outbox)").rows ==
               before
    end

    ctx = seed("create_missing_template_oban")
    assert submit(ctx, "text/vnd.turbo-stream.html").status == 500

    ctx = seed("foreign_edit")

    assert {:error, :not_found} =
             WebForm.load(Repo, ctx.user, hd(ctx.entry["before"]["trips"])["id"], %{})

    inactive = %{ctx.user | status: 0, active_until: nil}
    assert {:replay, _} = WebForm.load(Repo, inactive, nil, %{})

    Repo.query!("UPDATE users SET active_until = NULL, status = 0 WHERE id IN (8950,8951)")
    editor = Dawarich.Accounts.get(8951)
    assert {:ok, _} = WebForm.load(Repo, editor, 895_020, %{})
    session = RailsUser.session(8951)

    edit =
      RailsUser.signed_in(8951)
      |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, "/trips/895020/edit", nil)

    assert edit.status == 200

    rename = %{
      "_method" => "put",
      "authenticity_token" => RailsCsrf.masked_token(session),
      "trip" => %{"name" => "Inactive edit"}
    }

    assert post_form(session, Plug.Conn.Query.encode(rename), [], "/trips/895020").status == 303
    remove = Map.drop(rename, ["trip"]) |> Map.put("_method", "delete")
    assert post_form(session, Plug.Conn.Query.encode(remove), [], "/trips/895020").status == 303

    new =
      RailsUser.signed_in(8950)
      |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, "/trips/new", nil)

    assert new.status == 303
    assert get_resp_header(new, "location") == ["http://www.example.com/"]

    session = RailsUser.session(8950)

    raw =
      Plug.Conn.Query.encode(%{
        "authenticity_token" => RailsCsrf.masked_token(session),
        "trip" => %{
          "name" => "Inactive",
          "started_at" => "2026-10-03T09:00",
          "ended_at" => "2026-10-04T09:00"
        }
      })

    inactive_create = post_form(session, raw, [], "/trips")
    assert inactive_create.status == 303
    assert get_resp_header(inactive_create, "location") == ["http://www.example.com/"]

    Repo.query!("UPDATE users SET active_until = '3026-10-03' WHERE id = 8950")
    Ownership.put!(Repo, "command:trips.calculate", :oban)

    admitted =
      Plug.Test.conn(:post, "/trips", raw)
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> DawarichWeb.RailsAuth.call([])
      |> DawarichWeb.A8Request.call([])

    refute admitted.halted

    before =
      Repo.query!("SELECT (SELECT count(*) FROM trips), (SELECT count(*) FROM job_outbox)").rows

    Ownership.put!(Repo, "command:trips.calculate", :sidekiq)

    {{_, received}, owner_race} =
      forwarded(upstream, fn -> DawarichWeb.TripActions.call(admitted, :create) end)

    assert owner_race.status == 204
    assert received == raw

    assert Repo.query!("SELECT (SELECT count(*) FROM trips), (SELECT count(*) FROM job_outbox)").rows ==
             before

    Ownership.put!(Repo, "command:trips.calculate", :oban)

    oversized =
      RailsUser.session(8950, %{"padding" => Base.encode64(:crypto.strong_rand_bytes(4000))})

    committed =
      admitted
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(oversized))
      |> Map.put(:req_cookies, %Plug.Conn.Unfetched{aspect: :cookies})
      |> Map.put(:cookies, %Plug.Conn.Unfetched{aspect: :cookies})

    assert_raise DawarichWeb.RailsSession.Overflow, fn ->
      DawarichWeb.TripActions.call(committed, :create)
    end

    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id = 8950").rows == [[1]]
    assert commands() == []
  end

  defp functional(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> Enum.map(fn {tag, attrs, _} -> {tag, Enum.sort(attrs)} end)
  end
end
