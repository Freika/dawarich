defmodule DawarichWeb.DigestsNativeLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.{Repo, Accounts.Scope, Digests.Pages}
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-digest-upgrade")

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    digest!(user.id, %{
      year: 2024,
      distance: 50000,
      toponyms: [toponym("Germany", ["Berlin"])],
      monthly_distances: %{"3" => 38400, "4" => 11600},
      travel_patterns: %{"private_pattern" => "synthetic-unread-pattern"}
    })

    %{user: user}
  end

  test "Lite digest displays summary and never loads full pattern data", %{user: user} do
    System.put_env("SELF_HOSTED", "false")
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)

    {{:ok, data}, sql} =
      NativeAdminUI.queries(fn ->
        Pages.get(Scope.for_user(user, "en"), %{"year" => "2024"}, self_hosted: false)
      end)

    assert data.restricted
    refute Enum.any?(sql, &String.contains?(&1, "time_spent_by_location"))
    refute Map.has_key?(data, :monthly_distances)
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/digests/2024")
    assert has_element?(view, "#digest-upgrade")
    refute has_element?(view, "[phx-hook=NativeChart]")

    refute :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns) =~
             "synthetic-unread-pattern"

    render_click(view, "upgrade", %{})
    assert_redirect(view)
  end

  test "digest chart keeps localized monthly values across reconnect", %{user: user} do
    Repo.query!(
      "UPDATE users SET settings=settings || $2 WHERE id=$1",
      [user.id, %{"locale" => "de"}],
      log: false
    )

    for _ <- 1..2 do
      {:ok, view, _} = live(NativeAdminUI.conn(user), "/digests/2024")
      html = NativeAdminUI.html(view)

      [raw] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#digest-monthly-chart[phx-hook=NativeChart]")
        |> LazyHTML.attribute("data-chart")

      assert Jason.decode!(raw)["data"] == [["Mär", 38], ["Apr", 12]]
      refute html =~ "data-turbo"
      refute html =~ "Chartkick"
      refute :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns) =~ user.api_key
      assert NativeAdminUI.labels(html) == []
    end

    assert Repo.query!(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='digests.calculate_year'",
             [],
             log: false
           ).rows == [[0]]
  end

  test "native digest refuses foreign years without a same-route loop", %{user: user} do
    digest!(10801, %{year: 2023, distance: 9999})

    assert {:error, {:redirect, %{to: "/digests", flash: %{"alert" => "Digest not found"}}}} =
             live(NativeAdminUI.conn(user), "/digests/2023")
  end

  test "digest show windows retain full country city and first-visit totals", %{user: user} do
    countries = for n <- 1..61, do: toponym("Country #{n}", ["City #{n}"])

    first = %{
      "countries" => Enum.map(countries, & &1["country"]),
      "cities" => for(n <- 1..61, do: "City #{n}")
    }

    Repo.query!(
      "UPDATE digests SET toponyms=$2,first_time_visits=$3 WHERE user_id=$1",
      [user.id, countries, first],
      log: false
    )

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/digests/2024")
    data = :sys.get_state(view.pid).socket.assigns.data
    assert length(data.toponyms) == 50
    assert length(data.first_time_countries) == 50
    assert length(data.first_time_cities) == 10
    assert data.countries_count == 61
    assert data.cities_count == 61
    assert data.first_time_cities_count == 61
    assert data.places_more
    render_patch(view, "/digests/2024?page=2")
    second = :sys.get_state(view.pid).socket.assigns.data
    assert length(second.toponyms) == 11
    assert second.cities_count == 61
    refute second.places_more

    assert MapSet.disjoint?(
             MapSet.new(data.toponyms, & &1["country"]),
             MapSet.new(second.toponyms, & &1["country"])
           )
  end
end
