defmodule DawarichWeb.ImportsRemainingPagesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.{RailsUser, ParityHTML}
  alias DawarichWeb.{ImportsGate, RailsCsrf}
  alias Dawarich.Imports.Download

  setup do
    seed = File.read!("test/fixtures/imports_pages/seed.json") |> Jason.decode!()
    u = Enum.find(seed["users"], &(&1["id"] == 9801))
    RailsUser.insert!(%{id: u["id"], email: u["email"], settings: u["settings"]})
    other = RailsUser.insert!(%{id: 9803, email: "remaining-foreign@example.test"})
    r = Enum.find(seed["imports"], &(&1["id"] == 980_111))
    {:ok, created, 0} = DateTime.from_iso8601(r["created_at"])

    Repo.insert_all("imports", [
      %{
        id: 980_111,
        user_id: 9801,
        name: "normal.csv",
        source: 10,
        status: 2,
        raw_data: %{},
        additional_data_extraction: %{},
        additional_data_extraction_status: 5,
        created_at: DateTime.to_naive(created),
        updated_at: NaiveDateTime.utc_now()
      }
    ])

    for name <- ~w(20261001150000_import_download_requests 20261001170000_import_destroy_runs) do
      Repo.query!(File.read!("priv/repo/sql/#{name}.sql"), [], query_type: :text)
    end

    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.destroy", :oban)
    root = Path.join(System.tmp_dir!(), "remaining-pages-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    session = RailsUser.session(9801)

    %{
      user: 9801,
      other: other.id,
      root: root,
      session: session,
      token: RailsCsrf.masked_token(session),
      upstream: upstream!()
    }
  end

  defp request(c, method, path, body \\ "") do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("x-csrf-token", c.token)
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  defp form(source),
    do: Plug.Conn.Query.encode(%{"import" => %{"source" => source, "name" => "changed.csv"}})

  defp native!(conn, status) do
    assert conn.status == status
    assert get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
    conn
  end

  defp corpus!(html, name) do
    native = ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *")

    expected =
      File.read!("test/fixtures/imports_pages/pages/#{name}.html") |> ParityHTML.normalize()

    assert native == expected, ParityHTML.first_difference(native, expected)
  end

  test "normal owner show edit and invalid source render the Rails corpus", c do
    assert ImportsGate.native?(RailsUser.signed_in(c.user), %{"id" => "980111"})

    for locale <- ~w(en de es fr pl ca zh) do
      Repo.query!("UPDATE users SET settings=settings||$2 WHERE id=$1", [
        c.user,
        %{"locale" => locale}
      ])

      show = request(c, :get, "/imports/980111") |> native!(200)
      corpus!(show.resp_body, "show_csv_#{locale}")
      edit = request(c, :get, "/imports/980111/edit") |> native!(200)
      corpus!(edit.resp_body, "edit_csv_#{locale}")
      invalid = request(c, :patch, "/imports/980111", form("unknown")) |> native!(422)
      corpus!(invalid.resp_body, "invalid_source_#{locale}")

      assert [["normal.csv", 10]] ==
               Repo.query!("SELECT name,source FROM imports WHERE id=980111").rows
    end

    Repo.query!("UPDATE users SET settings=settings||$2 WHERE id=$1", [
      c.user,
      %{"locale" => "de"}
    ])

    conn =
      request(c, :post, "/imports/980111", form("google_phone_takeout") <> "&_method=patch")
      |> native!(303)

    assert get_resp_header(conn, "location") == ["http://www.example.com/imports"]

    assert rails_session(conn)["flash"]["flashes"]["notice"] ==
             "Import wurde erfolgreich aktualisiert."

    assert [["changed.csv", 3, 0]] ==
             Repo.query!(
               "SELECT name,source,additional_data_extraction_status FROM imports WHERE id=980111"
             ).rows
  end

  test "foreign import and route key hand back before any pipeline effect", c do
    refute ImportsGate.native?(RailsUser.signed_in(c.other), %{"id" => "980111"})
    foreign = %{c | session: RailsUser.session(c.other)}

    for {actor, method, path, body} <- [
          {foreign, :get, "/imports/980111/edit", ""},
          {foreign, :patch, "/imports/980111", form("csv")},
          {foreign, :delete, "/imports/980111", ""}
        ] do
      {{line, bytes}, conn} = forwarded(c.upstream, fn -> request(actor, method, path, body) end)

      assert {line, bytes, conn.status} ==
               {String.upcase(to_string(method)) <> " #{path} HTTP/1.1", body, 204}
    end

    previous = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, ["imports"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, previous) end)
    body = form("gpx") <> "&_method=patch"

    {{line, bytes}, conn} =
      forwarded(c.upstream, fn -> request(c, :post, "/imports/980111", body) end)

    assert {line, bytes, conn.status} == {"POST /imports/980111 HTTP/1.1", body, 204}

    assert [["normal.csv", 10, 2]] ==
             Repo.query!("SELECT name,source,status FROM imports WHERE id=980111").rows

    assert [] == Repo.query!("SELECT event_id FROM job_outbox").rows
  end

  test "non-GPX download and deletion preserve source bytes and cleanup", c do
    assert ImportsGate.native?(RailsUser.signed_in(c.user), %{"id" => "980111"})
    csv = "latitude,longitude,timestamp\n52,13,1700000000\n"
    {:ok, {_, zip}} = :zip.create(~c"points.csv.zip", [{~c"points.csv", csv}], [:memory])

    blob =
      Dawarich.RailsBlobFixture.create!(Repo, c.root, "points.csv.zip", zip,
        content_type: "application/zip",
        metadata: %{
          "dawarich_client_wrapped" => true,
          "dawarich_original_filename" => "points.csv"
        }
      )

    Repo.query!("UPDATE imports SET name='points.csv' WHERE id=980111")

    Repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',980111,$1,now())",
      [blob.id]
    )

    pending = request(c, :get, "/imports/980111/download") |> native!(202)
    assert get_resp_header(pending, "refresh") == ["3"]
    context = %{services: %{"local" => %{service: "local", root: c.root}}}
    assert :ok = Download.prepare!(Repo, c.user, 980_111, blob.id, context)
    conn = request(c, :get, "/imports/980111/download") |> native!(200)
    assert conn.resp_body == csv
    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

    assert get_resp_header(conn, "content-disposition") == [
             Dawarich.Storage.content_disposition("attachment", "points.csv")
           ]

    original = request(c, :get, "/imports/980111/download?original=1") |> native!(200)
    assert original.resp_body == zip

    assert get_resp_header(original, "content-disposition") == [
             Dawarich.Storage.content_disposition("attachment", "points.csv.zip")
           ]

    deleted = request(c, :delete, "/imports/980111") |> native!(303)
    assert rails_session(deleted)["flash"]["flashes"]["notice"] == "Import is being deleted."
    assert [[4]] == Repo.query!("SELECT status FROM imports WHERE id=980111").rows

    assert [[%{"import_id" => 980_111, "user_id" => 9801}]] =
             Repo.query!("SELECT payload FROM job_outbox WHERE command_type='imports.destroy'").rows
  end
end
