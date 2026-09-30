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

    %{upstream: upstream!()}
  end

  test "the fixture covers the points page in every zone and both Rails-only and Phoenix shapes" do
    assert Enum.frequencies_by(@data["cases"], &{&1["source"], &1["expect"]}) ==
             %{{"link", "phoenix"} => 84, {"hand", "phoenix"} => 8, {"hand", "rails"} => 28}
  end

  for {case_data, index} <- Enum.with_index(@data["cases"]) do
    @case case_data

    test "#{index}: #{case_data["name"]} (#{case_data["expect"]})", %{upstream: upstream} do
      session = RailsUser.session(@case["user_id"])
      body = URI.encode_query(@case["params"])
      path = @case["path"] || "/exports"

      submit = fn ->
        post_form(session, body, [{"x-csrf-token", RailsCsrf.masked_token(session)}], path)
      end

      case @case["expect"] do
        "phoenix" ->
          assert_like_rails(submit.(), @case)

        "rails" ->
          assert {{request_line, ^body}, %{status: 204}} = forwarded(upstream, submit)
          assert request_line == "POST #{path} HTTP/1.1"
          assert Repo.query!("SELECT count(*) FROM exports").rows == [[0]]
          assert commands() == []
      end
    end
  end

  defp assert_like_rails(conn, data) do
    rails = data["rails"]
    assert conn.status == rails["status"]

    for name <- @headers,
        do: assert(get_resp_header(conn, name) == List.wrap(rails["headers"][name]), name)

    assert Enum.all?(
             resp_header_names(conn),
             &(&1 in rails["header_set"] or &1 in @ed108_headers)
           )

    assert cookie_attribute_names(conn) == rails["set_cookie"]

    assert rails_session(conn)["flash"] == %{"discard" => [], "flashes" => rails["flash"]}

    assert [[id | row]] =
             Repo.query!(
               "SELECT id, #{Enum.join(@columns, ", ")} FROM exports WHERE user_id = $1",
               [data["user_id"]]
             ).rows

    assert @columns |> Enum.zip(Enum.map(row, &iso/1)) |> Map.new() == rails["export"]

    assert commands() == [
             [
               "exports.points_created",
               %{"export_id" => id, "user_id" => data["user_id"], "locale" => "en"}
             ]
           ]
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
