defmodule DawarichWeb.ImportsUploadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.{ImportsExportsSeeds, RailsUser}
  alias DawarichWeb.RailsCsrf
  alias Dawarich.Jobs.Ownership

  @form "application/x-www-form-urlencoded"

  setup do
    RailsUser.insert!(%{
      id: 7581,
      email: "upload-ui@example.test",
      settings: %{"timezone" => "Berlin"}
    })

    Ownership.put!(Repo, "command:imports.process_gpx", :oban)
    session = RailsUser.session(7581)
    root = Path.join(System.tmp_dir!(), "native-ui-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    %{session: session, token: RailsCsrf.masked_token(session), root: root, upstream: upstream!()}
  end

  defp request(c, method, path, body, headers \\ [{"content-type", @form}]) do
    headers
    |> Enum.reduce(build_conn(), fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("x-csrf-token", c.token)
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  defp rails_blob!(c, name, bytes),
    do: Dawarich.RailsBlobFixture.create!(Repo, c.root, name, bytes, user_id: 7581).signed_id

  defp create_body(signed_ids),
    do: Plug.Conn.Query.encode(%{"import" => %{"files" => signed_ids}})

  defp imports, do: Repo.query!("SELECT id,name,source FROM imports ORDER BY id").rows

  defp to_puma(c, method, path, body, headers \\ [{"content-type", @form}]) do
    {{line, received}, conn} =
      forwarded(c.upstream, fn -> request(c, method, path, body, headers) end)

    assert conn.status == 204
    {line, received}
  end

  test "a GPX file uploaded through Rails' direct upload is created natively", c do
    body = create_body([rails_blob!(c, "http.gpx", "<gpx><trk/></gpx>")])
    conn = request(c, :post, "/imports", body)

    assert conn.status == 303
    assert get_resp_header(conn, "location") == ["http://www.example.com/imports"]
    assert get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]

    assert rails_session(conn)["flash"]["flashes"] == %{
             "notice" => "1 files are queued to be imported in background"
           }

    assert [[_id, "http.gpx", 4]] = imports()

    assert [[%{"time_zone" => "Berlin"}]] =
             Repo.query!("SELECT payload FROM job_outbox").rows
             |> Enum.map(fn [p] -> [Map.take(p, ["time_zone"])] end)
  end

  test "the Rails form's multipart post is created natively; a file part or an oversized body reaches Puma",
       c do
    signed = rails_blob!(c, "form.gpx", "<gpx><trk/></gpx>")
    headers = [{"content-type", "multipart/form-data; boundary=XyZ"}]

    file_part =
      multipart([
        {~s(name="import[files][]"; filename="a.gpx"\r\nContent-Type: application/gpx+xml),
         "<gpx/>"}
      ])

    oversized =
      multipart([
        {~s(name="import[files][]"), signed},
        {~s(name="commit"), String.duplicate("x", 2_097_152)}
      ])

    for body <- [file_part, oversized],
        do:
          assert(to_puma(c, :post, "/imports", body, headers) == {"POST /imports HTTP/1.1", body})

    assert imports() == []

    body =
      multipart([
        {~s(name="import[files][]"), ""},
        {~s(name="import[files][]"), signed},
        {~s(name="commit"), "Create Import"}
      ])

    conn = request(c, :post, "/imports", body, headers)

    assert {conn.status, get_resp_header(conn, "x-dawarich-handler")} ==
             {303, ["phoenix-imports"]}

    assert [[_id, "form.gpx", 4]] = imports()
  end

  defp multipart(parts) do
    Enum.map_join(parts, fn {disposition, value} ->
      "--XyZ\r\nContent-Disposition: form-data; #{disposition}\r\n\r\n#{value}\r\n"
    end) <> "--XyZ--\r\n"
  end

  test "admitted GeoJSON and KML uploads are native while unclassified Google JSON is rejected",
       c do
    for {name, bytes} <- [
          {"points.geojson", ~s({"type":"FeatureCollection","features":[]})},
          {"route.kml", ~s(<?xml version="1.0"?><kml><Document/></kml>)}
        ] do
      body = create_body([rails_blob!(c, name, bytes)])
      conn = request(c, :post, "/imports", body)

      assert {conn.status, get_resp_header(conn, "x-dawarich-handler")} ==
               {303, ["phoenix-imports"]}
    end

    mixed = create_body([rails_blob!(c, "a.gpx", "<gpx/>"), rails_blob!(c, "b.kml", "<kml/>")])
    assert request(c, :post, "/imports", mixed).status == 303

    unknown = create_body([rails_blob!(c, "Records.json", ~s({"locations":[]}))])
    assert request(c, :post, "/imports", unknown).status == 422

    assert Enum.map(imports(), fn [_, name, source] -> {name, source} end) ==
             [{"points.geojson", 6}, {"route.kml", 9}, {"a.gpx", 4}, {"b.kml", 9}]

    assert [[4]] == Repo.query!("SELECT count(*) FROM active_storage_attachments").rows
  end

  test "requests Phoenix cannot answer exactly as Rails would reach Puma with their body", c do
    gpx = create_body([rails_blob!(c, "kept.gpx", "<gpx/>")])

    for {body, path, headers} <- [
          {gpx, "/imports?locale=de", [{"content-type", @form}]},
          {gpx <> "&utf8=%E2%9C%93", "/imports", [{"content-type", @form}]},
          {gpx <> "&_method=patch", "/imports", [{"content-type", @form}]},
          {gpx, "/imports", [{"content-type", @form}, {"accept", "text/vnd.turbo-stream.html"}]},
          {gpx, "/imports", [{"content-type", @form}, {"origin", "https://evil.example"}]},
          {~s({"import":{"files":["x"]}}), "/imports", [{"content-type", "application/json"}]},
          {"--b\r\n\r\n--b--\r\n", "/imports",
           [{"content-type", "multipart/form-data; boundary=b"}]}
        ] do
      assert to_puma(c, :post, path, body, headers) == {"POST #{path} HTTP/1.1", body}
    end

    assert to_puma(%{c | token: "tampered"}, :post, "/imports", gpx) ==
             {"POST /imports HTTP/1.1", gpx}

    assert imports() == []
  end

  test "owned GPX edits and deletes answer natively; other actions and imports reach Puma", c do
    Repo.query!(
      File.read!(
        Path.expand("../../priv/repo/sql/20261001170000_import_destroy_runs.sql", __DIR__)
      ),
      [],
      query_type: :text
    )

    Ownership.put!(Repo, "command:imports.destroy", :oban)
    other = RailsUser.insert!(%{id: 7582, email: "upload-foreign@example.test"})
    ImportsExportsSeeds.import!(%{id: 758_101, user_id: 7581, name: "owned.gpx"})
    ImportsExportsSeeds.import!(%{id: 758_102, user_id: other.id, name: "foreign.gpx"})
    ImportsExportsSeeds.import!(%{id: 758_106, user_id: 7581, name: "owned.csv", source: 10})
    params = Plug.Conn.Query.encode(%{"import" => %{"name" => "renamed.gpx", "source" => "gpx"}})

    for {method, path, body} <- [
          {:patch, "/imports/758102", params},
          {:delete, "/imports/758102", ""},
          {:post, "/imports/758106/extraction", ""},
          {:post, "/imports/758101", params},
          {:post, "/imports/758101", params <> "&_method=get"}
        ] do
      line = "#{method |> to_string() |> String.upcase()} #{path} HTTP/1.1"
      assert to_puma(c, method, path, body) == {line, body}
    end

    assert [[758_101, "owned.gpx", 4], [758_102, "foreign.gpx", 4], [758_106, "owned.csv", 10]] =
             imports()

    conn = request(c, :post, "/imports/758101", params <> "&_method=patch")
    assert conn.status == 303
    assert get_resp_header(conn, "location") == ["http://www.example.com/imports"]

    assert rails_session(conn)["flash"]["flashes"] == %{
             "notice" => "Import was successfully updated."
           }

    assert [["renamed.gpx", 4]] =
             Repo.query!("SELECT name,source FROM imports WHERE id=758101").rows

    conn = request(c, :delete, "/imports/758101", "")
    assert conn.status == 303
    assert rails_session(conn)["flash"]["flashes"] == %{"notice" => "Import is being deleted."}

    assert [[%{"import_id" => 758_101, "user_id" => 7581}]] =
             Repo.query!("SELECT payload FROM job_outbox WHERE command_type='imports.destroy'").rows
  end

  test "native delete is admitted with an empty current storage catalog", c do
    Repo.query!(
      File.read!(
        Path.expand("../../priv/repo/sql/20261001170000_import_destroy_runs.sql", __DIR__)
      ),
      [],
      query_type: :text
    )

    Ownership.put!(Repo, "command:imports.destroy", :oban)
    ImportsExportsSeeds.import!(%{id: 758_103, user_id: 7581, name: "catalogless.gpx"})
    Application.delete_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_services, %{})
    on_exit(fn -> Application.delete_env(:dawarich, :imports_services) end)

    assert request(c, :delete, "/imports/758103", "").status == 303
    assert [[4]] = Repo.query!("SELECT status FROM imports WHERE id=758103").rows
  end

  test "native manual extraction keeps exact options; refusals and foreign imports reach Puma",
       c do
    ImportsExportsSeeds.import!(%{
      id: 758_104,
      user_id: 7581,
      name: "manual.gpx",
      status: 1,
      raw_data: %{"waypoints_seen" => 1}
    })

    params = Plug.Conn.Query.encode(%{"trust_source" => "false"})

    assert to_puma(c, :post, "/imports/758104/extraction", params <> "&_method=patch") ==
             {"POST /imports/758104/extraction HTTP/1.1", params <> "&_method=patch"}

    conn = request(c, :post, "/imports/758104/extraction", params)
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/imports/758104"]

    assert rails_session(conn)["flash"]["flashes"] == %{"notice" => "Extraction queued."}

    assert [[1, %{"trust_source" => false}]] =
             Repo.query!(
               "SELECT additional_data_extraction_status,additional_data_extraction->'options' FROM imports WHERE id=758104"
             ).rows

    assert to_puma(c, :post, "/imports/758104/extraction", params) ==
             {"POST /imports/758104/extraction HTTP/1.1", params}

    other = RailsUser.insert!(%{id: 7583, email: "foreign-extraction@example.test"})

    ImportsExportsSeeds.import!(%{
      id: 758_105,
      user_id: other.id,
      name: "foreign-extraction.gpx",
      additional_data_extraction_status: 3
    })

    assert to_puma(c, :delete, "/imports/758105/extraction", "") ==
             {"DELETE /imports/758105/extraction HTTP/1.1", ""}

    Repo.query!("UPDATE imports SET status=2,additional_data_extraction_status=3 WHERE id=758104")
    conn = request(c, :post, "/imports/758104/extraction", "_method=delete")
    assert conn.status == 302

    assert [[2]] =
             Repo.query!("SELECT additional_data_extraction_status FROM imports WHERE id=758104").rows

    assert [["imports.extraction_requested"], ["imports.extraction_destroy_requested"]] =
             Repo.query!(
               "SELECT kind FROM phoenix.rails_commands WHERE payload->>'import_id'='758104' ORDER BY id"
             ).rows
  end
end
