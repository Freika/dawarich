defmodule DawarichWeb.UserDataTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.{RailsUser, ParityHTML}
  alias Dawarich.Jobs.Ownership
  @http Path.expand("../fixtures/user_data/http.json", __DIR__)

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    RailsUser.insert!(%{
      id: 9891,
      email: "backup-boundary@example.invalid",
      admin: false,
      status: 0,
      active_until: ~N[2020-01-01 00:00:00],
      settings: %{"timezone" => "UTC", "locale" => "en"}
    })

    session = RailsUser.session(9891)
    Ownership.put!(Repo, "command:users.export_data", :oban)
    Ownership.put!(Repo, "command:users.import_data", :oban)

    %{
      session: session,
      token: DawarichWeb.RailsCsrf.masked_token(session),
      root: dir,
      upstream: upstream!(),
      expected: File.read!(@http) |> Jason.decode!()
    }
  end

  test "backup endpoints preserve current user auth CSRF redirects and blank archive errors", c do
    route!()
    old = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
    end)

    for hosted <- ["true", "false"] do
      System.put_env("SELF_HOSTED", hosted)
      response = request(c, :get, "/settings/users/export")
      result(response, c.expected["en"]["export"])
    end

    assert [[0]] == Repo.query!("SELECT count(*) FROM exports").rows
    result(request(c, :post, "/settings/users/import", "archive="), c.expected["en"]["blank"])

    result(
      request(c, :post, "/settings/users/import", "archive=invalid"),
      c.expected["en"]["invalid"]
    )

    file = blob(c, "backup.zip")
    result(request(c, :post, "/settings/users/import", body(file)), c.expected["en"]["valid"])

    assert [[id, 9891, 8, 0, 5]] =
             Repo.query!(
               "SELECT id,user_id,source,status,additional_data_extraction_status FROM imports"
             ).rows

    assert [[file.id]] ==
             Repo.query!(
               "SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
               [id]
             ).rows

    Repo.query!("UPDATE active_storage_blobs SET filename='' WHERE id=$1", [file.id])
    result(request(c, :post, "/settings/users/import", body(file)), c.expected["en"]["failed"])
    assert [[1]] == Repo.query!("SELECT count(*) FROM imports").rows
    signed_out = request(%{c | session: %{}}, :get, "/settings/users/export")
    assert signed_out.status == 302
    assert get_resp_header(signed_out, "location") == ["http://www.example.com/users/sign_in"]
  end

  test "backup legacy trial count and size boundaries equal Rails", c do
    for locale <- ~w(en de es fr pl ca zh) do
      Repo.query!("DELETE FROM active_storage_attachments")
      Repo.query!("DELETE FROM imports")
      Repo.query!("DELETE FROM job_outbox")
      Repo.query!("DELETE FROM phoenix.rails_commands")

      Repo.query!(
        "UPDATE users SET status=2,subscription_source=0,settings=jsonb_set(settings,'{locale}',$1::text::jsonb) WHERE id=9891",
        [Jason.encode!(locale)]
      )

      Repo.query!(
        "INSERT INTO imports(user_id,name,created_at,updated_at) SELECT 9891,'trial boundary '||n,now(),now() FROM generate_series(1,4) n"
      )

      Repo.query!(
        "INSERT INTO imports(user_id,name,demo,created_at,updated_at) VALUES(9891,'demo boundary',true,now(),now())"
      )

      file = blob(c, "trial.zip")

      Repo.query!("UPDATE active_storage_blobs SET byte_size=$1 WHERE id=$2", [
        11 * 1024 * 1024,
        file.id
      ])

      for boundary <- ~w(count_four count_five size_limit size_over subscribed) do
        Repo.query!("UPDATE active_storage_blobs SET filename=$1 WHERE id=$2", [
          locale <> "-" <> boundary <> ".zip",
          file.id
        ])

        if boundary == "size_limit", do: Repo.query!("UPDATE imports SET demo=true")

        if boundary == "size_over",
          do:
            Repo.query!("UPDATE active_storage_blobs SET byte_size=$1 WHERE id=$2", [
              11 * 1024 * 1024 + 1,
              file.id
            ])

        if boundary == "subscribed" do
          Repo.query!("UPDATE users SET subscription_source=1 WHERE id=9891")

          Repo.query!(
            "INSERT INTO imports(user_id,name,created_at,updated_at) SELECT 9891,'subscribed boundary '||n,now(),now() FROM generate_series(1,5) n"
          )
        end

        [[imports, attachments, jobs]] =
          Repo.query!(
            "SELECT (SELECT count(*) FROM imports),(SELECT count(*) FROM active_storage_attachments),(SELECT count(*) FROM job_outbox)"
          ).rows

        expected = c.expected[locale]["trial"][boundary]
        result(request(c, :post, "/settings/users/import", body(file)), expected)

        assert [
                 [
                   imports + expected["imports_created"],
                   attachments + expected["attachments_created"],
                   jobs + expected["jobs_created"]
                 ]
               ] ==
                 Repo.query!(
                   "SELECT (SELECT count(*) FROM imports),(SELECT count(*) FROM active_storage_attachments),(SELECT count(*) FROM job_outbox)"
                 ).rows

        assert [] == commands()
      end
    end
  end

  test "backup hand-back keys forward original requests without effects", c do
    route!()
    old = Application.get_env(:dawarich, :rails_routes)
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, old) end)
    file = blob(c, "backup.zip")

    for key <- ~w(user_data settings),
        {method, path, bytes} <- [
          {:get, "/settings/users/export", ""},
          {:post, "/settings/users/import", body(file)}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])

      assert {{line, ^bytes}, %{status: 204}} =
               forwarded(c.upstream, fn -> request(c, method, path, bytes) end)

      assert line == "#{String.upcase(to_string(method))} #{path} HTTP/1.1"
      assert empty_effects?()
    end

    Application.put_env(:dawarich, :rails_routes, [])

    for headers <- [
          [{"content-type", "application/json"}],
          [{"content-type", "multipart/form-data; boundary=synthetic"}]
        ] do
      bytes = "unsupported-body"

      assert {{"POST /settings/users/import HTTP/1.1", ^bytes}, %{status: 204}} =
               forwarded(c.upstream, fn ->
                 request(c, :post, "/settings/users/import", bytes, headers)
               end)

      assert empty_effects?()
    end
  end

  test "backup form and endpoint result equal Rails markup in all shipped locales", c do
    route!()

    for locale <- ~w(en de es fr pl ca zh) do
      html =
        DawarichWeb.AccountParts.import_dialog(%{
          __changed__: nil,
          locale: locale,
          upload_url: "UPLOAD",
          legacy_trial: false,
          rails_csrf_token: "CSRF"
        })
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert ParityHTML.fragment(html, "form[action='/settings/users/import']") ==
               ParityHTML.normalize(c.expected[locale]["form"])

      assert html =~ ~s(name="archive")
      refute html =~ ~s(name="import[files][]")

      Repo.query!(
        "UPDATE users SET settings=jsonb_set(settings,'{locale}',$1::text::jsonb) WHERE id=9891",
        [Jason.encode!(locale)]
      )

      result(request(c, :get, "/settings/users/export"), c.expected[locale]["export"])
      result(request(c, :post, "/settings/users/import", "archive="), c.expected[locale]["blank"])

      result(
        request(c, :post, "/settings/users/import", "archive=invalid"),
        c.expected[locale]["invalid"]
      )

      file = blob(c, locale <> "-backup.zip")
      result(request(c, :post, "/settings/users/import", body(file)), c.expected[locale]["valid"])
      Repo.query!("UPDATE active_storage_blobs SET filename='' WHERE id=$1", [file.id])

      result(
        request(c, :post, "/settings/users/import", body(file)),
        c.expected[locale]["failed"]
      )
    end
  end

  test "tokenless session GET export and CSRF-checked POST restore run natively", c do
    route!()
    response = request(%{c | token: nil}, :get, "/settings/users/export")

    assert {response.status, get_resp_header(response, "x-dawarich-handler")} ==
             {302, ["phoenix-user-data"]}

    assert [["users.export_data", %{"user_id" => 9891, "time_zone" => "UTC", "locale" => "en"}]] ==
             Repo.query!("SELECT command_type,payload FROM job_outbox").rows

    file = blob(c, "backup.zip")

    for token <- [nil, "invalid"] do
      assert {{"POST /settings/users/import HTTP/1.1", bytes}, %{status: 204}} =
               forwarded(c.upstream, fn ->
                 request(%{c | token: token}, :post, "/settings/users/import", body(file))
               end)

      assert bytes == body(file)
      assert [[0]] == Repo.query!("SELECT count(*) FROM imports").rows
    end

    response = request(c, :post, "/settings/users/import", body(file))

    assert {response.status, get_resp_header(response, "x-dawarich-handler")} ==
             {302, ["phoenix-user-data"]}

    assert [
             [
               "users.import_data",
               %{"import_id" => id, "user_id" => 9891, "time_zone" => "UTC", "locale" => "en"}
             ]
           ] =
             Repo.query!(
               "SELECT command_type,payload FROM job_outbox WHERE command_type='users.import_data'"
             ).rows

    assert [[id]] ==
             Repo.query!(
               "SELECT record_id FROM active_storage_attachments WHERE record_type='Import'"
             ).rows

    Ownership.put!(Repo, "command:users.export_data", :sidekiq)
    assert request(c, :get, "/settings/users/export").status == 302

    assert [["users.export_data", %{"user_id" => 9891, "time_zone" => "UTC", "locale" => "en"}]] ==
             commands()

    Ownership.put!(Repo, "command:users.import_data", :sidekiq)
    other = blob(c, "other.zip")
    assert request(c, :post, "/settings/users/import", body(other)).status == 302
    assert [_, ["users.import_data", %{"import_id" => _, "user_id" => 9891}]] = commands()
  end

  defp route! do
    for {method, action, pipe} <- [
          {"GET", "export", :user_data_export},
          {"POST", "import", :user_data_import}
        ] do
      assert %{plug: DawarichWeb.UserDataController, pipe_through: [^pipe]} =
               Phoenix.Router.route_info(
                 DawarichWeb.Router,
                 method,
                 ["settings", "users", action],
                 "www.example.com"
               )
    end
  end

  defp result(conn, expected) do
    assert conn.status == expected["status"]
    assert get_resp_header(conn, "location") == ["http://www.example.com" <> expected["location"]]
    assert rails_session(conn)["flash"]["flashes"] == expected["flash"]
  end

  defp empty_effects?,
    do:
      Repo.query!(
        "SELECT (SELECT count(*) FROM imports)+(SELECT count(*) FROM active_storage_attachments)+(SELECT count(*) FROM job_outbox)+(SELECT count(*) FROM phoenix.rails_commands)"
      ).rows == [[0]]

  defp blob(c, name),
    do:
      Dawarich.RailsBlobFixture.create!(Repo, c.root, name, "synthetic ZIP",
        content_type: "application/zip",
        user_id: 9891
      )

  defp body(blob), do: "archive=" <> URI.encode_www_form(blob.signed_id)

  defp request(c, method, path, bytes \\ "", headers \\ []) do
    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(bytes)))

    conn = if c.token, do: put_req_header(conn, "x-csrf-token", c.token), else: conn

    Enum.reduce(headers, conn, fn {key, value}, acc -> put_req_header(acc, key, value) end)
    |> dispatch(DawarichWeb.Endpoint, method, path, bytes)
  end
end
