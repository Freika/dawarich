defmodule DawarichWeb.StandaloneShareAssetsTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Build.Importmap
  alias DawarichWeb.{Assets, PublicFiles}

  @endpoint DawarichWeb.Endpoint
  @moduletag :tmp_dir
  @id "a9f20000-0000-4000-8000-000000000001"
  @packages ~w(actioncable.esm.js activestorage.esm.js rails-ujs.js turbo.min.js
    stimulus.min.js stimulus-loading.js chartkick.js Chart.bundle.js trix.js actiontext.esm.js)

  setup %{tmp_dir: root} do
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})
    old = Application.fetch_env!(:dawarich, :public_files)
    key = {Assets, :rails_imports}
    imports = :persistent_term.get(key, %{})
    project = Dawarich.RailsRoot.root()

    logical =
      for dir <- ~w(app/javascript vendor/javascript),
          path <- Path.wildcard(Path.join(project, dir <> "/**/*.{js,jsm}")),
          do: Path.relative_to(path, Path.join(project, dir))

    manifest =
      Map.new(logical ++ @packages, fn path ->
        {path, Path.rootname(path) <> "-synthetic" <> Path.extname(path)}
      end)

    for {logical, digest} <- manifest do
      file = Path.join(root, "public/assets/" <> digest)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "export {};\n// " <> logical)
    end

    maplibre = Path.join(root, "public/maplibre/6.4.1/maplibre-gl.mjs")
    File.mkdir_p!(Path.dirname(maplibre))
    File.write!(maplibre, "export {};")
    File.mkdir_p!(Path.join(root, "config"))

    File.write!(
      Path.join(root, "config/sprockets-manifest.json"),
      Jason.encode!(%{assets: manifest})
    )

    exported = Importmap.export(project, manifest) |> IO.iodata_to_binary() |> Jason.decode!()
    :persistent_term.put(key, exported["imports"])

    Application.put_env(:dawarich, :public_files, %{
      old
      | root: Path.join(root, "public"),
        env: %{"RAILS_ENV" => "test", "APPLICATION_HOSTS" => "www.example.com"}
    })

    on_exit(fn ->
      Application.put_env(:dawarich, :public_files, old)
      :persistent_term.put(key, imports)

      for name <- ~w(DAWARICH_RAILS SELF_HOSTED) do
        if env[name], do: System.put_env(name, env[name]), else: System.delete_env(name)
      end
    end)

    %{manifest: manifest}
  end

  defp host_conn, do: %{build_conn() | req_headers: [{"host", "www.example.com"}]}

  test "standalone phrase unlock serves every public importmap module and extensionless import",
       ctx do
    id = user!()
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        user_id: id,
        resource_type: 2,
        name: "Synthetic timeline",
        magic_phrase: "synthetic-phrase",
        settings: %{"start_date" => "2026-05-09", "end_date" => "2026-05-12"},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    gate = get(host_conn(), "/s/" <> @id)
    assert gate.status == 401
    session = Dawarich.Test.RailsFormRequests.rails_session(gate)
    form = LazyHTML.from_document(gate.resp_body)

    [token] =
      form |> LazyHTML.query("input[name=authenticity_token]") |> LazyHTML.attribute("value")

    unlocked =
      Dawarich.Test.RailsFormRequests.post_form(
        session,
        URI.encode_query(%{"phrase" => "synthetic-phrase", "authenticity_token" => token}),
        [],
        "/s/" <> @id <> "/unlock"
      )

    assert unlocked.status == 302
    page = unlocked |> recycle() |> get("/s/" <> @id)
    assert page.status == 200
    assert page.resp_body =~ ~s(data-controller="shared-trip-map")

    json =
      page.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("script[type=importmap]")
      |> LazyHTML.text()

    imports = Jason.decode!(json)["imports"]
    assert map_size(imports) > 100

    for {name, path} <- imports do
      conn = get(host_conn(), path)
      assert conn.status == 200, name <> ": " <> path
      assert get_resp_header(conn, "content-type") == ["text/javascript"], path
    end

    assert get(host_conn(), "/assets/channels").status == 200

    for {logical, digest} <- ctx.manifest do
      stem = String.replace_suffix(logical, Path.extname(logical), "")
      stem = String.replace_suffix(stem, "/index", "")
      path = "/assets/" <> stem
      conn = get(host_conn(), path)
      assert conn.status == 200, path

      assert conn.resp_body ==
               File.read!(
                 Path.join(
                   Application.fetch_env!(:dawarich, :public_files).root,
                   "assets/" <> digest
                 )
               ),
             path
    end

    for path <- ~w(/assets/absent /assets/%2e%2e/config/importmap.rb) do
      refute PublicFiles.call(
               %{Plug.Test.conn(:get, path) | req_headers: [{"host", "www.example.com"}]},
               []
             ).halted
    end
  end
end
