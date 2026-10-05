defmodule DawarichWeb.ExportsDeleteTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.RailsUser

  setup do
    RailsUser.insert!(%{id: 9811, email: "exports-delete@example.test"})
    RailsUser.insert!(%{id: 9812, email: "exports-foreign@example.test"})

    Repo.query!(
      "INSERT INTO exports(id,user_id,name,status,file_format,file_type,created_at,updated_at) VALUES(981101,9811,'backup.zip',2,2,1,now(),now()),(981102,9812,'foreign.zip',2,2,1,now(),now()),(981103,9811,'post.zip',2,2,1,now(),now())"
    )

    session = RailsUser.session(9811)
    root = Path.join(System.tmp_dir!(), "exports-delete-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      session: session,
      token: DawarichWeb.RailsCsrf.masked_token(session),
      root: root,
      upstream: upstream!()
    }
  end

  defp request(c, method, path, body \\ "", headers \\ []) do
    Enum.reduce(headers, build_conn(), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("x-csrf-token", c.token)
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  defp route!(method) do
    route =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        method,
        ["exports", "981101"],
        "www.example.com"
      )

    assert %{plug: DawarichWeb.ExportsDelete, plug_opts: :delete} = route
  end

  test "export delete is owner scoped and stages the Rails 303 flash", c do
    route!("DELETE")
    assert {:error, :not_found} == Dawarich.Exports.Delete.call(Repo, 9811, "981102")
    body = "_method=DELETE"

    {{line, bytes}, foreign} =
      forwarded(c.upstream, fn -> request(c, :post, "/exports/981102", body) end)

    assert {line, bytes, foreign.status} == {"POST /exports/981102 HTTP/1.1", body, 204}
    {{_, ""}, missing} = forwarded(c.upstream, fn -> request(c, :delete, "/exports/999999") end)
    assert missing.status == 204
    blob = Dawarich.RailsBlobFixture.create!(Repo, c.root, "backup.zip", "synthetic export")

    Repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',981101,$1,now())",
      [blob.id]
    )

    conn = request(c, :delete, "/exports/981101")

    assert {conn.status, get_resp_header(conn, "x-dawarich-handler")} ==
             {303, ["phoenix-exports"]}

    assert get_resp_header(conn, "location") == ["http://www.example.com/exports"]

    assert rails_session(conn)["flash"]["flashes"] == %{
             "notice" => "Export was successfully destroyed."
           }

    assert [[981_102], [981_103]] == Repo.query!("SELECT id FROM exports ORDER BY id").rows

    assert [] ==
             Repo.query!(
               "SELECT id FROM active_storage_attachments WHERE record_type='Export' AND record_id=981101"
             ).rows

    assert [
             [
               "exports.purge",
               %{"export_id" => 981_101, "user_id" => 9811, "blob_ids" => [blob.id]}
             ]
           ] == Repo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows

    assert File.read!(
             Dawarich.Storage.disk_path(
               c.root,
               Repo.query!("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id]).rows
               |> hd()
               |> hd()
             )
           ) == "synthetic export"
  end

  test "DELETE and POST export deletion run natively with Rails session and CSRF", c do
    route!("POST")

    admission =
      Plug.Test.conn(:post, "/exports/981103", "_method=DELETE")
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", "14")
      |> put_req_header("x-csrf-token", c.token)
      |> DawarichWeb.Api.Body.call([])
      |> DawarichWeb.RailsAuth.call([])

    assert :ok == DawarichWeb.RailsForm.admission(admission, allowed_overrides: ["DELETE"])

    for {method, path, body} <- [
          {:delete, "/exports/981101", ""},
          {:post, "/exports/981103", "_method=DELETE"}
        ] do
      conn = request(c, method, path, body)

      assert {conn.status, get_resp_header(conn, "x-dawarich-handler")} ==
               {303, ["phoenix-exports"]}
    end

    assert [[981_102]] == Repo.query!("SELECT id FROM exports").rows

    create =
      "start_at=2024-03-01+00%3A00%3A00+%2B0100&end_at=2024-03-31+00%3A00%3A00+%2B0100&file_format=json"

    assert request(c, :post, "/exports", create).status == 302

    Repo.query!(
      "INSERT INTO exports(id,user_id,name,status,file_format,file_type,created_at,updated_at) VALUES(981104,9811,'invalid-admission.zip',2,2,1,now(),now())"
    )

    for {actor, path, body, headers} <- [
          {%{c | token: "invalid"}, "/exports/981104", "_method=DELETE", []},
          {c, "/exports/981104?_method=DELETE", "", []},
          {c, "/exports/981104", "_method=DELETE&_method=POST", []},
          {c, "/exports/981104", "_method=POST&_method=DELETE", []},
          {c, "/exports/981104", "_method=DELETE", [{"x-http-method-override", "DELETE"}]}
        ] do
      {{line, bytes}, conn} =
        forwarded(c.upstream, fn -> request(actor, :post, path, body, headers) end)

      assert {line, bytes, conn.status} == {"POST #{path} HTTP/1.1", body, 204}
    end

    assert [[981_104]] == Repo.query!("SELECT id FROM exports WHERE id=981104").rows
  end
end
