defmodule DawarichWeb.A12f3aERequestClosureTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{
      id: 9721,
      email: "exports-closure@example.test",
      settings: %{"timezone" => "UTC", "locale" => "en"}
    })

    Ownership.put!(Repo, "command:exports.points", :oban)
    session = RailsUser.session(9721)
    %{session: session, token: DawarichWeb.RailsCsrf.masked_token(session)}
  end

  @tag a12f3a_e01: true
  test "E01: export index and format submission matches current Rails contract without a native-owner Rails effect",
       c do
    capture = File.read!("test/fixtures/user_data/a12f3a-e02.json") |> Jason.decode!()

    cases =
      Enum.filter(
        capture["cases"],
        &(&1["source"] == "hand" and
            &1["name"] not in ["method override to delete", "client parameter"])
      )

    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    for hosted <- ["true", "false", nil], data <- cases do
      if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")
      Repo.query!("DELETE FROM exports")
      Repo.query!("DELETE FROM job_outbox")
      body = URI.encode_query(data["params"])
      conn = post_form(c.session, body, [{"x-csrf-token", c.token}], data["path"] || "/exports")
      expected = data["rails"]
      assert conn.status == expected["status"], data["name"]
      assert conn.resp_body == ""
      assert get_resp_header(conn, "location") == [expected["headers"]["location"]]
      assert Map.has_key?(conn.resp_cookies, "_dawarich_session"), data["name"]
      assert rails_session(conn)["flash"]["flashes"] == expected["flash"]

      columns =
        ~w(name status file_format file_type start_at end_at url error_message processing_started_at)

      actual = Repo.query!("SELECT #{Enum.join(columns, ",")} FROM exports").rows
      actual = Enum.map(actual, fn row -> Map.new(Enum.zip(columns, Enum.map(row, &iso/1))) end)
      assert actual == List.wrap(expected["export"]), data["name"] <> " " <> inspect(actual)
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[expected["export_jobs"]]]
      assert commands() == []
    end
  end

  @tag a12f3a_e04: true
  @tag :tmp_dir
  test "E04: backup http producer and authority matches current Rails contract without a native-owner Rails effect",
       c do
    Ownership.put!(Repo, "command:users.export_data", :oban)
    Ownership.put!(Repo, "command:users.import_data", :oban)

    expected =
      File.read!("test/fixtures/user_data/a12f3a-e04.json")
      |> Jason.decode!()
      |> get_in(["summary", "en"])

    export = get_request(c, "/settings/users/export?id=999999")
    assert export.status == expected["export"]["status"]

    assert Enum.map(get_resp_header(export, "location"), &URI.parse(&1).path) == [
             expected["export"]["location"]
           ]

    assert [[%{"user_id" => 9721}]] =
             Repo.query!("SELECT payload FROM job_outbox WHERE command_type='users.export_data'").rows

    for {kind, body} <- [{"array", "archive[]=x"}, {"object", "archive[nested]=x"}] do
      conn = post_form(c.session, body, [{"x-csrf-token", c.token}], "/settings/users/import")
      assert conn.status == expected["containers"][kind]["status"]
      assert rails_session(conn)["flash"]["flashes"] == expected["containers"][kind]["flash"]
    end

    assert commands() == []
  end

  defp get_request(c, path) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, path, nil)
  end

  defp iso(%NaiveDateTime{} = value),
    do: NaiveDateTime.to_iso8601(%{value | microsecond: {elem(value.microsecond, 0), 6}}) <> "Z"

  defp iso(value), do: value
end
