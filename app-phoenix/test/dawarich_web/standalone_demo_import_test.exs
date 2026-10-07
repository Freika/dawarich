defmodule DawarichWeb.StandaloneDemoImportTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  @tag :sa_g44_demo_bounds
  test "browser demo load bounds country work and preserves immediate owned data" do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    Dawarich.Seeds.Countries.run(Repo)

    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "demo-bounds@example.invalid"
      })

    event = "demo-bounds-#{user.id}"
    :telemetry.attach(event, [:dawarich, :repo, :query], &__MODULE__.country_query/4, nil)
    on_exit(fn -> :telemetry.detach(event) end)
    session = RailsUser.session(user.id)
    body = URI.encode_query(%{"authenticity_token" => RailsCsrf.masked_token(session)})

    response =
      build_conn()
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
      |> put_req_header("accept", "text/vnd.turbo-stream.html, text/html, application/xhtml+xml")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> dispatch(@endpoint, :post, "/settings/onboarding/demo_data", body)

    assert response.status == 302
    assert URI.parse(hd(get_resp_header(response, "location"))).path == "/map/v2"

    assert Dawarich.Test.RailsFormRequests.rails_session(response)["flash"]["flashes"]["notice"] =~
             "Demo"

    assert Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [user.id], log: false).rows ==
             [[17988]]

    assert Repo.query!("SELECT count(*) FROM tracks WHERE user_id=$1 AND demo=true", [user.id],
             log: false
           ).rows == [[118]]

    countries =
      Repo.query!(
        "SELECT country_id,count(*) FROM points WHERE user_id=$1 GROUP BY country_id ORDER BY country_id",
        [user.id],
        log: false
      ).rows

    {query, params} = Process.get(:demo_country_query)
    Repo.query!("UPDATE points SET country_id=NULL WHERE user_id=$1", [user.id], log: false)

    [[[%{"Plan" => plan}]]] =
      Repo.query!("EXPLAIN (ANALYZE, FORMAT JSON) " <> query, params, log: false).rows

    country_parts = Enum.find(nodes(plan), &(&1["Subplan Name"] == "CTE country_parts"))
    assert country_parts["Actual Rows"] <= 100

    assert Repo.query!(
             "SELECT country_id,count(*) FROM points WHERE user_id=$1 GROUP BY country_id ORDER BY country_id",
             [user.id],
             log: false
           ).rows == countries
  end

  def country_query(_, _, %{query: query, params: params}, _) do
    if String.starts_with?(query, "WITH bounds"),
      do: Process.put(:demo_country_query, {query, params})
  end

  defp nodes(node), do: [node | Enum.flat_map(node["Plans"] || [], &nodes/1)]
end
