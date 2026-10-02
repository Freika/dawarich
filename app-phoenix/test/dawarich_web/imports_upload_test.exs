defmodule DawarichWeb.ImportsUploadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  alias Dawarich.Jobs.Ownership

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

    %{session: session, token: RailsCsrf.masked_token(session), root: root}
  end

  defp request(c, method, path, body, type) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("content-type", type)
    |> put_req_header("x-csrf-token", c.token)
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  test "actual native direct upload protocol, binary PUT and bracketed create form", c do
    bytes = "<gpx><trk/></gpx>"

    body =
      Jason.encode!(%{
        "blob" => %{
          "filename" => "http.gpx",
          "byte_size" => byte_size(bytes),
          "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
          "content_type" => "application/gpx+xml"
        }
      })

    conn = request(c, :post, "/imports/direct_uploads", body, "application/json")
    assert conn.status == 200
    blob = Jason.decode!(conn.resp_body)
    assert blob["signed_id"]
    assert blob["direct_upload"]["url"] =~ "/imports/uploads/"
    path = URI.parse(blob["direct_upload"]["url"]).path
    assert request(c, :put, path, bytes, "application/gpx+xml").status == 204
    params = Plug.Conn.Query.encode(%{"import" => %{"files" => [blob["signed_id"]]}})
    conn = request(c, :post, "/imports", params, "application/x-www-form-urlencoded")
    assert conn.status == 303
    assert get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
    assert [[4]] = Repo.query!("SELECT source FROM imports WHERE name='http.gpx'").rows

    assert [[%{"time_zone" => "Berlin"}]] =
             Repo.query!("SELECT payload FROM job_outbox").rows
             |> Enum.map(fn [p] -> [Map.take(p, ["time_zone"])] end)
  end

  test "native upload CSRF rejection returns an error without creating a blob", c do
    before = Repo.query!("SELECT count(*) FROM active_storage_blobs").rows

    conn =
      request(%{c | token: "invalid"}, :post, "/imports/direct_uploads", "{}", "application/json")

    assert conn.status == 422
    assert get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
    assert before == Repo.query!("SELECT count(*) FROM active_storage_blobs").rows
  end

  test "malformed native protocol shapes are rejected without mutation", c do
    before = Repo.query!("SELECT count(*) FROM imports").rows

    conn =
      request(
        c,
        :post,
        "/imports/direct_uploads",
        Jason.encode!(%{"blob" => "invalid"}),
        "application/json"
      )

    assert conn.status == 422

    conn =
      request(c, :post, "/imports", Jason.encode!(%{"import" => "invalid"}), "application/json")

    assert conn.status == 422
    assert before == Repo.query!("SELECT count(*) FROM imports").rows
  end

  test "native edits and deletes are scoped to the authenticated owner with integer commands",
       c do
    Repo.query!(
      File.read!(
        Path.expand("../../priv/repo/sql/20261001170000_import_destroy_runs.sql", __DIR__)
      ),
      [],
      query_type: :text
    )

    Ownership.put!(Repo, "command:imports.destroy", :oban)
    other = RailsUser.insert!(%{id: 7582, email: "upload-foreign@example.test"})
    Dawarich.Test.ImportsExportsSeeds.import!(%{id: 758_101, user_id: 7581, name: "owned.gpx"})

    Dawarich.Test.ImportsExportsSeeds.import!(%{
      id: 758_102,
      user_id: other.id,
      name: "foreign.gpx"
    })

    params = Plug.Conn.Query.encode(%{"import" => %{"name" => "renamed.gpx", "source" => "gpx"}})

    for {method, body} <- [{:patch, params}, {:delete, ""}] do
      conn = request(c, method, "/imports/758102", body, "application/x-www-form-urlencoded")
      assert conn.status == 404
      assert get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
    end

    assert [["foreign.gpx", 2]] =
             Repo.query!("SELECT name,status FROM imports WHERE id=758102").rows

    assert request(c, :patch, "/imports/758101", params, "application/x-www-form-urlencoded").status ==
             303

    assert [["renamed.gpx", 4]] =
             Repo.query!("SELECT name,source FROM imports WHERE id=758101").rows

    assert request(c, :delete, "/imports/758101", "", "application/x-www-form-urlencoded").status ==
             303

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

    Dawarich.Test.ImportsExportsSeeds.import!(%{
      id: 758_103,
      user_id: 7581,
      name: "catalogless.gpx"
    })

    Application.delete_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_services, %{})
    on_exit(fn -> Application.delete_env(:dawarich, :imports_services) end)

    assert request(c, :delete, "/imports/758103", "", "application/x-www-form-urlencoded").status ==
             303

    assert [[4]] = Repo.query!("SELECT status FROM imports WHERE id=758103").rows
  end

  test "native manual extraction forms preserve exact options and enforce actor on removal", c do
    Dawarich.Test.ImportsExportsSeeds.import!(%{
      id: 758_104,
      user_id: 7581,
      name: "manual.gpx",
      status: 1,
      raw_data: %{"waypoints_seen" => 1}
    })

    params = Plug.Conn.Query.encode(%{"trust_source" => "false"})

    assert request(
             c,
             :post,
             "/imports/758104/extraction",
             params,
             "application/x-www-form-urlencoded"
           ).status == 303

    assert [[1, %{"trust_source" => false}]] =
             Repo.query!(
               "SELECT additional_data_extraction_status,additional_data_extraction->'options' FROM imports WHERE id=758104"
             ).rows

    assert request(
             c,
             :post,
             "/imports/758104/extraction",
             params,
             "application/x-www-form-urlencoded"
           ).status == 422

    other = RailsUser.insert!(%{id: 7583, email: "foreign-extraction@example.test"})

    Dawarich.Test.ImportsExportsSeeds.import!(%{
      id: 758_105,
      user_id: other.id,
      name: "foreign-extraction.gpx",
      additional_data_extraction_status: 3
    })

    assert request(
             c,
             :delete,
             "/imports/758105/extraction",
             "",
             "application/x-www-form-urlencoded"
           ).status == 404

    Repo.query!("UPDATE imports SET status=2,additional_data_extraction_status=3 WHERE id=758104")
    params = Plug.Conn.Query.encode(%{"_method" => "delete"})

    assert request(
             c,
             :post,
             "/imports/758104/extraction",
             params,
             "application/x-www-form-urlencoded"
           ).status == 303

    assert [[2]] =
             Repo.query!("SELECT additional_data_extraction_status FROM imports WHERE id=758104").rows

    assert [["imports.extraction_requested"], ["imports.extraction_destroy_requested"]] =
             Repo.query!(
               "SELECT kind FROM phoenix.rails_commands WHERE payload->>'import_id'='758104' ORDER BY id"
             ).rows
  end
end
