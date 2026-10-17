defmodule DawarichWeb.StorageRoutesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0]
  alias Dawarich.Test.RailsUser
  alias Dawarich.{Storage, RailsMessages}
  alias DawarichWeb.ActiveStorageUrls

  setup do
    RailsUser.insert!(%{id: 9821, email: "storage-routes@example.test"})
    session = RailsUser.session(9821)
    root = Path.join(System.tmp_dir!(), "storage-routes-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    previous = Application.get_env(:dawarich, :rails_root)
    Application.put_env(:dawarich, :rails_root, root)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, previous)
      File.rm_rf!(root)
    end)

    %{
      session: session,
      token: DawarichWeb.RailsCsrf.masked_token(session),
      root: root,
      disk: Path.join(root, "storage"),
      upstream: upstream!()
    }
  end

  defp request(c, method, path, body, headers, authenticated \\ true) do
    conn =
      Enum.reduce(headers, build_conn(), fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    conn =
      if authenticated,
        do:
          conn
          |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
          |> put_req_header("x-csrf-token", c.token),
        else: conn

    conn
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, method, path, if(body == "", do: nil, else: body))
  end

  defp path(url), do: URI.parse(url).path

  defp upload_body(bytes),
    do:
      Jason.encode!(%{
        "blob" => %{
          "filename" => "binary.dat",
          "byte_size" => byte_size(bytes),
          "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
          "content_type" => "application/octet-stream"
        }
      })

  defp mounted! do
    info =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        "POST",
        ["rails", "active_storage", "direct_uploads"],
        "www.example.com"
      )

    assert %{plug: DawarichWeb.StorageRoutes, plug_opts: :direct_upload} = info
  end

  test "native direct upload disk PUT and download match A12b Rails protocol", c do
    mounted!()
    bytes = <<0, 1, 2, 255, 0, 100>>

    conn =
      request(c, :post, "/rails/active_storage/direct_uploads", upload_body(bytes), [
        {"content-type", "application/json"}
      ])

    assert {conn.status, get_resp_header(conn, "x-dawarich-handler")} ==
             {200, ["phoenix-active-storage"]}

    body = Jason.decode!(conn.resp_body)
    assert body["byte_size"] == 6
    assert body["content_type"] == "application/octet-stream"
    {:ok, id} = RailsMessages.verified_blob_id(body["signed_id"], DateTime.utc_now())

    assert [[6, checksum]] =
             Repo.query!("SELECT byte_size,checksum FROM active_storage_blobs WHERE id=$1", [id]).rows

    assert checksum == Base.encode64(:crypto.hash(:md5, bytes))
    put = path(body["direct_upload"]["url"])

    invalid =
      request(
        c,
        :put,
        put,
        <<0, 1, 2, 255, 0, 101>>,
        [{"content-type", "application/octet-stream"}],
        false
      )

    assert invalid.status == 422
    refute File.exists?(Storage.disk_path(c.disk, body["key"]))

    assert request(c, :put, put, bytes, [{"content-type", "application/octet-stream"}], false).status ==
             204

    assert File.read!(Storage.disk_path(c.disk, body["key"])) == bytes

    redirect =
      request(
        c,
        :get,
        "/rails/active_storage/blobs/redirect/#{body["signed_id"]}/binary.dat",
        "",
        [],
        false
      )

    assert redirect.status == 302
    disk = redirect |> get_resp_header("location") |> hd() |> path()
    full = request(c, :get, disk, "", [], false)
    assert {full.status, full.resp_body} == {200, bytes}
    assert get_resp_header(full, "content-type") == ["application/octet-stream"]
    partial = request(c, :get, disk, "", [{"range", "bytes=1-3"}], false)
    assert {partial.status, partial.resp_body} == {206, <<1, 2, 255>>}
    assert get_resp_header(partial, "content-range") == ["bytes 1-3/6"]
    assert request(c, :head, disk, "", [], false).resp_body == ""
    proxy = %{build_conn() | path_info: ~w(rails active_storage blobs proxy signed binary.dat)}
    assert DawarichWeb.StorageGate.native?(proxy, %{})

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    before = Repo.query!("SELECT count(*) FROM active_storage_blobs").rows

    proxied =
      request(c, :get, "/rails/active_storage/blobs/proxy/signed/binary.dat", "", [], false)

    assert proxied.status == 404
    assert proxied.resp_body == ""
    assert get_resp_header(proxied, "x-dawarich-handler") == ["phoenix-active-storage"]
    assert Repo.query!("SELECT count(*) FROM active_storage_blobs").rows == before
    assert File.read!(Storage.disk_path(c.disk, body["key"])) == bytes
  end

  test "route extraction preserves every existing LiveView session" do
    for {path, action} <- [{"/stats", :index}, {"/stats/2024", :year}] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")
      assert route.plug == DawarichWeb.InsightsRedirect
      assert route.plug_opts == action
      assert route.pipe_through == [:native_data_request, :browser, :rails_user]
      refute Map.has_key?(route, :phoenix_live_view)
    end

    for path <-
          ~w(/notifications /notifications/17 /imports/new /imports/17 /imports/17/edit /imports /exports /stats/2024/2 /digests /digests/2024 /trips /trips/17 /points /insights) do
      route =
        Phoenix.Router.route_info(
          DawarichWeb.Router,
          "GET",
          String.split(path, "/", trim: true),
          "www.example.com"
        )

      if String.starts_with?(path, "/trips") do
        assert route.pipe_through == [:native_m6_browser, :rails_user]
        assert {_, _, opts, %{name: :native_m6, extra: extra}} = route.phoenix_live_view
        assert opts[:container] == {:div, class: "contents"}

        assert extra == %{
                 session: {DawarichWeb.MapLiveAuth, :live_session, []},
                 root_layout: {DawarichWeb.Layouts, :native_root},
                 layout: false
               }
      else
        assert route.pipe_through ==
                 if(route[:native_page],
                   do: [:native_data_request, :browser, :rails_user],
                   else: [:browser, :rails_user]
                 )

        native =
          path in ~w(/stats /stats/2024 /stats/2024/2 /digests /digests/2024 /points /insights)

        jobs = String.starts_with?(path, ["/imports", "/exports", "/notifications"])

        expected =
          cond do
            jobs -> :native_jobs
            native -> :native_data
            String.starts_with?(path, "/trips") -> :trips_map_dependency
            true -> :rails_pages
          end

        assert {_, _, opts, %{name: ^expected, extra: extra}} = route.phoenix_live_view
        assert opts[:container] == {:div, class: "contents"}

        assert extra.session ==
                 {if(jobs, do: DawarichWeb.NativeJobsAuth, else: DawarichWeb.NativeAuth),
                  :live_session, []}

        assert extra.layout == {DawarichWeb.Layouts, :app}

        assert extra.root_layout ==
                 {DawarichWeb.Layouts, if(native or jobs, do: :native_root, else: :root)}

        assert Enum.map(extra.on_mount, & &1.id) == [
                 cond do
                   native -> {DawarichWeb.NativeDataAuth, :require_user}
                   jobs -> {DawarichWeb.NativeJobsAuth, :require_user}
                   true -> {DawarichWeb.LiveAuth, :default}
                 end
               ]
      end
    end
  end

  test "tag pages and native settings pages live in the native live_session" do
    for path <-
          ~w(/places /tags /tags/new /tags/17/edit /settings/general /settings/visits /settings/integrations /settings/trek_sources/17/select_trips /users/edit) do
      route =
        Phoenix.Router.route_info(
          DawarichWeb.Router,
          "GET",
          String.split(path, "/", trim: true),
          "www.example.com"
        )

      assert route.pipe_through == [:browser, :rails_user]
      assert {_, _, _opts, %{name: :native_pages, extra: extra}} = route.phoenix_live_view
      assert extra.root_layout == {DawarichWeb.Layouts, :native_root}
      assert Enum.map(extra.on_mount, & &1.id) == [{DawarichWeb.NativeAuth, :require_user}]
      refute Map.has_key?(route, :rails_gate)
    end
  end

  test "retired export overrides have no effects while active_storage rollback preserves bytes",
       c do
    mounted!()

    Repo.query!(
      "INSERT INTO exports(id,user_id,name,status,file_format,file_type,created_at,updated_at) VALUES(982101,9821,'rollback.zip',2,2,1,now(),now())"
    )

    previous = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, previous) end)
    Application.put_env(:dawarich, :rails_routes, ["exports"])
    form = "_method=DELETE"

    conn =
      request(c, :post, "/exports/982101", form, [
        {"content-type", "application/x-www-form-urlencoded"}
      ])

    assert conn.status == 404
    assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    assert [[982_101]] == Repo.query!("SELECT id FROM exports WHERE id=982101").rows
    assert [] == Repo.query!("SELECT id FROM phoenix.rails_commands").rows

    binary = <<0, 255, 4, 0>>
    metadata = upload_body(binary)

    admitted =
      request(c, :post, "/rails/active_storage/direct_uploads", metadata, [
        {"content-type", "application/json"}
      ])

    assert admitted.status == 200
    blob = Jason.decode!(admitted.resp_body)
    put = path(blob["direct_upload"]["url"])

    assert request(c, :put, put, binary, [{"content-type", "application/octet-stream"}], false).status ==
             204

    data = %{
      key: blob["key"],
      filename: "binary.dat",
      content_type: "application/octet-stream",
      service_name: "local"
    }

    disk =
      ActiveStorageUrls.service_url(
        %{service: "local", root: c.disk},
        data,
        nil,
        "http://www.example.com",
        DateTime.utc_now()
      )
      |> path()

    assert request(c, :get, disk, "", [], false).resp_body == binary

    Application.put_env(:dawarich, :rails_routes, ["active_storage"])

    Dawarich.Jobs.Ownership.put!(Repo, "command:users.export_data", :oban)
    scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(9821), "en")
    assert {:ok, :deleted} = Dawarich.Exports.delete(scope, 982_101)

    [[before]] = Repo.query!("SELECT count(*) FROM active_storage_blobs").rows

    for {method, url, body, headers} <- [
          {:post, "/rails/active_storage/direct_uploads", metadata,
           [{"content-type", "application/json"}]},
          {:put, put, <<8, 9, 0, 255>>, [{"content-type", "application/octet-stream"}]},
          {:get, disk, "", []}
        ] do
      result = request(c, method, url, body, [{"accept", "application/json"} | headers], false)
      assert result.status == if(method == :get, do: 200, else: 422)
      if method == :get, do: assert(result.resp_body == binary)
      assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    end

    assert [[before]] == Repo.query!("SELECT count(*) FROM active_storage_blobs").rows
    assert File.read!(Storage.disk_path(c.disk, blob["key"])) == binary
  end
end
