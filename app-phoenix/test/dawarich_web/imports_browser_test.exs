defmodule DawarichWeb.ImportsBrowserTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Test.{ImportsExportsSeeds, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    owner = RailsUser.insert!(%{id: 75995, email: "browser-import-owner@example.test"})
    foreign = RailsUser.insert!(%{id: 75996, email: "browser-import-foreign@example.test"})

    record =
      ImportsExportsSeeds.import!(%{
        id: 759_950,
        user_id: owner.id,
        source: 3,
        raw_data: %{},
        additional_data_extraction: %{},
        additional_data_extraction_status: 0
      })

    Dawarich.Jobs.Ownership.put!(Repo, "command:enhanced_import.extract_gpx", :oban)
    session = RailsUser.session(owner.id)

    %{
      owner: owner,
      foreign: foreign,
      record: record,
      session: session,
      token: RailsCsrf.masked_token(session)
    }
  end

  @tag :g44_imports_extraction
  test "native extraction queues distrusted classification while retired POST envelopes refuse",
       c do
    headers = [
      {"accept", "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"},
      {"turbo-frame", "import-759950-extraction"}
    ]

    for body <- [
          "trust_source=false",
          "authenticity_token=invalid&trust_source=false",
          "authenticity_token=" <>
            URI.encode_www_form(c.token) <> "&trust_source[unexpected]=false"
        ] do
      denied = post_form(c.session, body, headers, "/imports/759950/extraction")
      assert denied.status == 404
    end

    assert [] == Repo.query!("SELECT id FROM oban.oban_jobs").rows

    conn = RailsUser.signed_in(c.owner.id) |> RailsUser.connecting_as(c.owner.id)
    {:ok, view, _} = live(conn, "/imports/759950")
    render_hook(view, "extract_import", %{"trust_source" => "false"})
    assert render(view) =~ "Queued"

    assert [[1, %{"trust_source" => false}]] =
             Repo.query!(
               "SELECT additional_data_extraction_status,additional_data_extraction->'options' FROM imports WHERE id=$1",
               [c.record.id]
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker' AND args->>'import_id'=$1",
               [to_string(c.record.id)]
             ).rows
  end

  @tag :g44_imports_foreign
  test "native foreign import reads refuse safely and retired writes have no effects",
       c do
    session = RailsUser.session(c.foreign.id)
    token = RailsCsrf.masked_token(session)

    for suffix <- ["", "/edit"] do
      conn = RailsUser.signed_in(c.foreign.id) |> RailsUser.connecting_as(c.foreign.id)
      assert {:error, {:redirect, %{to: "/imports"}}} = live(conn, "/imports/759950" <> suffix)
    end

    assert get(RailsUser.signed_in(c.foreign.id), "/imports/759950/download").status == 404

    for {method, path, body} <- [
          {:patch, "/imports/759950", "import[name]=forbidden"},
          {:delete, "/imports/759950", ""},
          {:post, "/imports/759950/extraction", "trust_source=false"}
        ] do
      conn =
        build_conn()
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", to_string(byte_size(body)))
        |> put_req_header("x-csrf-token", token)
        |> dispatch(@endpoint, method, path, body)

      assert conn.status == 404
      assert get_resp_header(conn, "x-dawarich-handler") == []
    end

    assert [[c.record.name, 2, 0]] ==
             Repo.query!(
               "SELECT name,status,additional_data_extraction_status FROM imports WHERE id=$1",
               [c.record.id]
             ).rows

    assert [] == Repo.query!("SELECT event_id FROM job_outbox").rows
    assert [] == Repo.query!("SELECT id FROM phoenix.rails_commands").rows
    assert [] == Repo.query!("SELECT id FROM oban.oban_jobs").rows
  end
end
