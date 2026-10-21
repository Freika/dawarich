defmodule DawarichWeb.ImportsUploadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{ImportsExportsSeeds, RailsUser}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Imports
  alias Dawarich.Imports.UploadCreate
  alias Dawarich.Jobs.Ownership
  @form "application/x-www-form-urlencoded"

  setup do
    user =
      RailsUser.insert!(%{
        id: 7581,
        email: "upload-ui@example.test",
        settings: %{"timezone" => "Berlin"}
      })

    for type <-
          ~w(imports.process_gpx imports.process_normal imports.destroy enhanced_import.extract_gpx enhanced_import.destroy_gpx),
        do: Ownership.put!(Repo, "command:" <> type, :oban)

    session = RailsUser.session(user.id)
    root = Path.join(System.tmp_dir!(), "native-ui-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    %{
      user: user,
      scope: Scope.for_user(user, "en"),
      session: session,
      token: DawarichWeb.RailsCsrf.masked_token(session),
      root: root,
      upstream: Dawarich.Test.RailsFormRequests.upstream!()
    }
  end

  defp request(c, method, path, body, headers) do
    Enum.reduce(headers, build_conn(), fn {name, value}, conn ->
      put_req_header(conn, name, value)
    end)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("x-csrf-token", c.token)
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  defp retired(c, method, path, body, headers \\ [{"content-type", @form}]) do
    before = imports()
    assert request(c, method, path, body, headers).status == 404
    assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    assert imports() == before
  end

  defp rails_blob!(c, name, bytes),
    do: Dawarich.RailsBlobFixture.create!(Repo, c.root, name, bytes, user_id: c.user.id).signed_id

  defp create_body(signed_ids),
    do: Plug.Conn.Query.encode(%{"import" => %{"files" => signed_ids}})

  defp imports, do: Repo.query!("SELECT id,name,source FROM imports ORDER BY id").rows

  defp consume(c, files),
    do: UploadCreate.create(Repo, c.user, files, DawarichWeb.ImportsContext.for_user(c.user))

  test "legacy owned GPX receipt consumption preserves source and captured timezone", c do
    signed = rails_blob!(c, "http.gpx", "<gpx><trk/></gpx>")
    retired(c, :post, "/imports", create_body([signed]))
    assert {:ok, [_]} = consume(c, [signed])
    assert [[_id, "http.gpx", 4]] = imports()

    assert [[%{"time_zone" => "Berlin"}]] =
             Repo.query!("SELECT payload FROM job_outbox").rows
             |> Enum.map(fn [p] -> [Map.take(p, ["time_zone"])] end)
  end

  test "retired multipart upload vectors have no effect while the valid receipt remains consumable",
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

    valid =
      multipart([
        {~s(name="import[files][]"), ""},
        {~s(name="import[files][]"), signed},
        {~s(name="commit"), "Create Import"}
      ])

    for body <- [file_part, oversized, valid], do: retired(c, :post, "/imports", body, headers)
    assert imports() == []
    assert {:ok, [_]} = consume(c, ["", signed])
    assert [[_id, "form.gpx", 4]] = imports()
  end

  defp multipart(parts) do
    Enum.map_join(parts, fn {disposition, value} ->
      "--XyZ\r\nContent-Disposition: form-data; #{disposition}\r\n\r\n#{value}\r\n"
    end) <> "--XyZ--\r\n"
  end

  test "owned receipt formats preserve GeoJSON KML mixed files and unclassified Google refusal",
       c do
    for {name, bytes} <- [
          {"points.geojson", ~s({"type":"FeatureCollection","features":[]})},
          {"route.kml", ~s(<?xml version="1.0"?><kml><Document/></kml>)}
        ] do
      assert {:ok, [_]} = consume(c, [rails_blob!(c, name, bytes)])
    end

    assert {:ok, [_, _]} =
             consume(c, [rails_blob!(c, "a.gpx", "<gpx/>"), rails_blob!(c, "b.kml", "<kml/>")])

    assert {:error, _} = consume(c, [rails_blob!(c, "Records.json", ~s({"locations":[]}))])

    assert Enum.map(imports(), fn [_, name, source] -> {name, source} end) == [
             {"points.geojson", 6},
             {"route.kml", 9},
             {"a.gpx", 4},
             {"b.kml", 9}
           ]

    assert [[4]] == Repo.query!("SELECT count(*) FROM active_storage_attachments").rows
  end

  test "every retired upload query body origin csrf and transport variant refuses without replay",
       c do
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
        ],
        do: retired(c, :post, path, body, headers)

    retired(%{c | token: "tampered"}, :post, "/imports", gpx)
    assert imports() == []
  end

  test "scoped GPX edit and delete preserve owner effects and foreign refusal after HTTP retirement",
       c do
    other = RailsUser.insert!(%{id: 7582, email: "upload-foreign@example.test"})
    ImportsExportsSeeds.import!(%{id: 758_101, user_id: c.user.id, name: "owned.gpx"})
    ImportsExportsSeeds.import!(%{id: 758_102, user_id: other.id, name: "foreign.gpx"})
    ImportsExportsSeeds.import!(%{id: 758_106, user_id: c.user.id, name: "owned.csv", source: 10})
    params = Plug.Conn.Query.encode(%{"import" => %{"name" => "renamed.gpx", "source" => "gpx"}})

    for {method, path, body} <- [
          {:patch, "/imports/758102", params},
          {:delete, "/imports/758102", ""},
          {:post, "/imports/758106/extraction", ""},
          {:post, "/imports/758101", params},
          {:post, "/imports/758101", params <> "&_method=get"}
        ],
        do: retired(c, method, path, body)

    assert {:error, :not_found} = Imports.update(c.scope, 758_102, %{"name" => "forged"})
    assert {:error, :not_found} = Imports.delete(c.scope, 758_102)

    assert {:ok, _} =
             Imports.update(c.scope, 758_101, %{"name" => "renamed.gpx", "source" => "gpx"})

    assert [["renamed.gpx", 4]] =
             Repo.query!("SELECT name,source FROM imports WHERE id=758101").rows

    assert {:ok, _} = Imports.delete(c.scope, 758_101)

    assert [[%{"import_id" => 758_101, "user_id" => c.user.id}]] ==
             Repo.query!("SELECT payload FROM job_outbox WHERE command_type='imports.destroy'").rows
  end

  test "scoped native delete is admitted with an empty current storage catalog", c do
    ImportsExportsSeeds.import!(%{id: 758_103, user_id: c.user.id, name: "catalogless.gpx"})
    Application.delete_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_services, %{})
    on_exit(fn -> Application.delete_env(:dawarich, :imports_services) end)
    assert {:ok, _} = Imports.delete(c.scope, 758_103)
    assert [[4]] = Repo.query!("SELECT status FROM imports WHERE id=758103").rows
  end

  test "scoped manual extraction keeps exact options duplicate refusal and foreign removal refusal",
       c do
    ImportsExportsSeeds.import!(%{
      id: 758_104,
      user_id: c.user.id,
      name: "manual.gpx",
      status: 1,
      raw_data: %{"waypoints_seen" => 1}
    })

    params = Plug.Conn.Query.encode(%{"trust_source" => "false"})
    retired(c, :post, "/imports/758104/extraction", params <> "&_method=patch")
    assert {:ok, _} = Imports.extract(c.scope, 758_104, %{"trust_source" => "false"})

    assert [[1, %{"trust_source" => false}]] =
             Repo.query!(
               "SELECT additional_data_extraction_status,additional_data_extraction->'options' FROM imports WHERE id=758104"
             ).rows

    assert {:error, _} = Imports.extract(c.scope, 758_104, %{"trust_source" => "false"})
    other = RailsUser.insert!(%{id: 7583, email: "foreign-extraction@example.test"})

    ImportsExportsSeeds.import!(%{
      id: 758_105,
      user_id: other.id,
      name: "foreign-extraction.gpx",
      additional_data_extraction_status: 3
    })

    assert {:error, :not_found} = Imports.remove_extraction(c.scope, 758_105)
    Repo.query!("UPDATE imports SET status=2,additional_data_extraction_status=3 WHERE id=758104")
    assert {:ok, _} = Imports.remove_extraction(c.scope, 758_104)

    assert [[2]] =
             Repo.query!("SELECT additional_data_extraction_status FROM imports WHERE id=758104").rows

    assert [["Dawarich.EnhancedImport.NormalWorker"]] =
             Repo.query!("SELECT worker FROM oban.oban_jobs WHERE args->>'import_id'='758104'").rows

    assert [["enhanced_import.destroy_gpx"]] =
             Repo.query!(
               "SELECT command_type FROM job_outbox WHERE payload->>'import_id'='758104'"
             ).rows

    assert [] = Repo.query!("SELECT kind FROM phoenix.rails_commands").rows
  end
end
