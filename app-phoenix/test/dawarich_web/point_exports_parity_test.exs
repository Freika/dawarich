defmodule DawarichWeb.PointExportsParityTest do
  use Dawarich.IngestCase, async: false

  import Dawarich.Test.RailsFormRequests
  import Plug.Conn, only: [get_resp_header: 2]

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @fixture "test/fixtures/point_exports/cases.json"
  @external_resource @fixture
  @data @fixture |> File.read!() |> Jason.decode!()
  @headers ~w(location content-type cache-control vary x-frame-options x-xss-protection x-content-type-options x-permitted-cross-domain-policies referrer-policy)
  @ed108_headers ~w(etag x-request-id x-runtime)
  @wire_only ~w(content-length)
  @columns ~w(name status file_format file_type start_at end_at url error_message processing_started_at)

  setup do
    for user <- @data["users"] do
      RailsUser.insert!(%{
        id: user["id"],
        email: user["email"],
        settings: user["settings"],
        status: user["status"],
        plan: user["plan"],
        active_until: user["active_until"] && NaiveDateTime.from_iso8601!(user["active_until"])
      })
    end

    Dawarich.Jobs.Ownership.put!(Repo, "command:exports.points", :oban)
    :ok
  end

  test "the fixture covers the points page in every zone and both Rails-only and Phoenix shapes" do
    assert Enum.frequencies_by(@data["cases"], &{&1["source"], &1["expect"]}) ==
             %{{"link", "phoenix"} => 84, {"hand", "phoenix"} => 8, {"hand", "rails"} => 28}
  end

  for {case_data, index} <- Enum.with_index(@data["cases"]) do
    @case case_data

    test "#{index}: #{case_data["name"]} (#{case_data["expect"]})" do
      session = RailsUser.session(@case["user_id"])
      body = URI.encode_query(@case["params"])
      path = @case["path"] || "/exports"

      submit = fn ->
        post_form(session, body, [{"x-csrf-token", RailsCsrf.masked_token(session)}], path)
      end

      if @case["params"]["_method"] not in [nil, "post"] or
           Map.has_key?(@case["params"], "client") do
        assert submit.().status == 422
        assert Repo.query!("SELECT count(*) FROM exports").rows == [[0]]
        assert commands() == []
        assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
      else
        assert_like_rails(submit.(), @case)
      end
    end
  end

  defp assert_like_rails(conn, data) do
    rails = data["rails"]
    assert conn.status == rails["status"]
    assert conn.resp_body == ""

    assert MapSet.new(resp_header_names(conn)) ==
             rails["header_set"]
             |> MapSet.new()
             |> MapSet.difference(MapSet.new(@ed108_headers ++ @wire_only))

    for name <- @headers,
        do: assert(get_resp_header(conn, name) == List.wrap(rails["headers"][name]), name)

    assert cookie_attribute_names(conn) == rails["set_cookie"]

    assert rails_session(conn)["flash"] == %{"discard" => [], "flashes" => rails["flash"]}

    rows =
      Repo.query!(
        "SELECT id, #{Enum.join(@columns, ", ")} FROM exports WHERE user_id = $1",
        [data["user_id"]]
      ).rows

    assert commands() == []

    if rails["export"] do
      assert [[id | row]] = rows
      assert @columns |> Enum.zip(Enum.map(row, &iso/1)) |> Map.new() == rails["export"]

      if rails["export_jobs"] == 1 do
        assert [[2, %{"export_id" => ^id, "user_id" => user_id, "time_zone" => zone}, ^id, key]] =
                 Repo.query!(
                   "SELECT command_version,payload,aggregate_id,dedupe_key FROM job_outbox"
                 ).rows

        assert user_id == data["user_id"]
        assert key == "points-export:#{id}"
        settings = Enum.find(@data["users"], &(&1["id"] == user_id))["settings"]
        assert zone == Dawarich.UserTimeZone.name(settings, Repo)
      else
        assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
      end
    else
      assert rows == []
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    end
  end

  defp resp_header_names(conn),
    do: conn.resp_headers |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

  defp cookie_attribute_names(conn) do
    case get_resp_header(conn, "set-cookie") do
      [header] ->
        header
        |> String.split("; ")
        |> tl()
        |> Enum.map(&(&1 |> String.split("=") |> hd() |> String.downcase()))
        |> Enum.sort()

      [] ->
        nil
    end
  end

  defp iso(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time) <> "Z"
  defp iso(value), do: value
end
