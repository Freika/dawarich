defmodule DawarichWeb.A12f3aIClosureTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{ImportsExportsSeeds, RailsUser}
  alias Dawarich.Jobs.Ownership

  setup do
    user = RailsUser.insert!(%{id: 7811, email: "closure-import@example.test"})
    session = RailsUser.session(user.id)
    root = Path.join(System.tmp_dir!(), "imports-closure-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})
    Ownership.put!(Repo, "command:imports.process_gpx", :oban)
    Ownership.put!(Repo, "command:imports.process_normal", :oban)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, previous)
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    %{user: user, session: session, root: root}
  end

  @tag a12f3a_i02: true
  test "I02: upload forms and signed/raw files matches current Rails contract without a native-owner Rails effect",
       c do
    for {files, expected} <- Enum.zip([nil, [], [""]], capture("i02")) do
      params = if is_nil(files), do: %{}, else: %{"import" => %{"files" => files}}
      response = request(c, :post, "/imports", params)
      assert response.status == expected["status"]
      assert get_resp_header(response, "location") == [expected["location"]]

      assert Dawarich.Test.RailsFormRequests.rails_session(response)["flash"]["flashes"]["alert"] ==
               expected["alert"]

      assert Repo.query!("SELECT count(*) FROM imports").rows == [[0]]
    end

    blob = Dawarich.RailsBlobFixture.create!(Repo, c.root, "Leipzig.gpx", "<gpx/>")

    rejected =
      request(c, :post, "/imports", %{"import" => %{"files" => [blob.signed_id, "invalid"]}})

    assert rejected.status == 422
    assert Repo.query!("SELECT count(*) FROM imports").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM active_storage_attachments").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]

    response = request(c, :post, "/imports", %{"import" => %{"files" => [blob.signed_id]}})
    assert response.status == 303
    assert Repo.query!("SELECT name,source FROM imports").rows == [["Leipzig.gpx", 4]]
    assert Repo.query!("SELECT command_type FROM job_outbox").rows == [["imports.process_gpx"]]
    assert commands() == []
  end

  @tag a12f3a_i03: true
  test "I03: import rename source and put updates matches current Rails contract without a native-owner Rails effect",
       c do
    ImportsExportsSeeds.import!(%{
      id: 781_101,
      user_id: c.user.id,
      name: "normal.csv",
      source: 10
    })

    for {method, params, expected} <- [
          {:put, %{"name" => "renamed.csv", "source" => "geojson"}, ["renamed.csv", 6]},
          {:patch, %{"name" => "", "source" => "gpx"}, ["renamed.csv", 6]},
          {:post, %{"name" => "override.csv", "source" => "gpx"}, ["override.csv", 4]}
        ] do
      body = %{"import" => params}
      body = if method == :post, do: Map.put(body, "_method", "put"), else: body
      response = request(c, method, "/imports/781101", body)
      assert response.status == 303
      assert get_resp_header(response, "location") == ["http://www.example.com/imports"]
      assert Repo.query!("SELECT name,source FROM imports WHERE id=781101").rows == [expected]
    end

    invalid = request(c, :put, "/imports/781101", %{"import" => %{"source" => "unknown"}})
    assert invalid.status == 422
    assert invalid.resp_body =~ "Source"

    assert Repo.query!("SELECT name,source FROM imports WHERE id=781101").rows == [
             ["override.csv", 4]
           ]

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert commands() == []
  end

  @tag a12f3a_i04: true
  test "I04: delete and extraction request transitions matches current Rails contract without a native-owner Rails effect",
       c do
    ImportsExportsSeeds.import!(%{
      id: 781_104,
      user_id: c.user.id,
      name: "extract.gpx",
      status: 2,
      raw_data: %{"waypoints_seen" => 1}
    })

    Ownership.put!(Repo, "command:enhanced_import.extract_gpx", :oban)
    Ownership.put!(Repo, "command:enhanced_import.destroy_gpx", :oban)

    assert request(c, :post, "/imports/781104/extraction", %{"trust_source" => "false"}).status ==
             302

    assert Repo.query!("SELECT command_type,payload FROM job_outbox").rows == [
             ["enhanced_import.extract_gpx", %{"import_id" => 781_104, "lock_attempt" => 1}]
           ]

    assert commands() == []
    assert request(c, :post, "/imports/781104/extraction", %{}).status == 303
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[1]]
    Repo.query!("UPDATE imports SET additional_data_extraction_status=3 WHERE id=781104")
    assert request(c, :delete, "/imports/781104/extraction", %{}).status == 302

    assert Repo.query!("SELECT command_type FROM job_outbox ORDER BY command_type DESC").rows == [
             ["enhanced_import.extract_gpx"],
             ["enhanced_import.destroy_gpx"]
           ]

    assert Repo.query!("SELECT additional_data_extraction_status FROM imports WHERE id=781104").rows ==
             [[2]]

    assert commands() == []
  end

  defp capture(task) do
    Path.expand("../fixtures/imports_pages/a12f3a-#{task}.json", __DIR__)
    |> File.read!()
    |> Jason.decode!()
  end

  defp request(c, method, path, params) do
    body = Plug.Conn.Query.encode(params)

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(c.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end
end
