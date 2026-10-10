defmodule DawarichWeb.NativePublicPagesTest do
  use Dawarich.DataCase, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsUser, StatsSeeds}

  test "public digest rendering keeps source totals localized chart values and no owner key or private chrome" do
    RailsUser.insert!(%{
      id: 19002,
      email: "native-public-digest@example.invalid",
      api_key: "synthetic-owner-secret",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    uuid = Ecto.UUID.generate()

    StatsSeeds.digest!(19002, %{
      year: 2024,
      distance: 12000,
      monthly_distances: Enum.map(1..12, &[Integer.to_string(&1), &1 * 1000]),
      toponyms: [StatsSeeds.toponym("Germany", ["Berlin"])],
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: %{"enabled" => true, "expiration" => nil}
    })

    for method <- ["GET", "HEAD"] do
      conn = build_conn(method, "/shared/digest/" <> uuid)
      conn = %{conn | params: %{}, path_params: %{"uuid" => uuid}}

      conn =
        conn
        |> assign(:locale, "de")
        |> assign(:base_url, "http://www.example.com")
        |> assign(:current_user, nil)
        |> assign(:self_hosted, true)
        |> assign(:now, DateTime.utc_now())

      conn = apply(DawarichWeb.NativePublicPage, :call, [conn, :digest])
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]

      if method == "HEAD" do
        assert conn.resp_body == ""
      else
        assert conn.resp_body =~ "2024"
        assert conn.resp_body =~ "Germany"
        assert conn.resp_body =~ "public_charts.js"
        refute conn.resp_body =~ "synthetic-owner-secret"
        refute conn.resp_body =~ "api_key"
        refute conn.resp_body =~ "importmap"
        refute conn.resp_body =~ "app.js"
        doc = LazyHTML.from_document(conn.resp_body)
        [chart] = doc |> LazyHTML.query("[data-chart]") |> LazyHTML.attribute("data-chart")
        payload = Jason.decode!(chart)
        assert length(payload["data"]) == 12
        assert hd(payload["data"]) == ["Jan", 1.0]
        assert List.last(payload["data"]) == ["Dez", 12.0]

        assert Enum.empty?(
                 LazyHTML.query(doc, "[phx-hook], [data-controller], #notification-bell")
               )
      end
    end
  end

  test "bounded public digest names preserve full per-country totals and more indicators" do
    RailsUser.insert!(%{
      id: 19004,
      email: "native-public-counts@example.invalid",
      settings: %{"timezone" => "UTC"}
    })

    uuid = Ecto.UUID.generate()

    StatsSeeds.digest!(19004, %{
      year: 2024,
      toponyms: [StatsSeeds.toponym("Germany", Enum.map(1..61, &"City #{&1}"))],
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: %{"enabled" => true, "expiration" => nil}
    })

    assert {:ok, page} = Dawarich.Sharing.Pages.report(:digest, uuid, self_hosted: true)
    [country] = page.digest.toponyms
    assert country["cities_count"] == 61
    assert length(country["cities"]) == 5
    conn = build_conn("GET", "/shared/digest/" <> uuid)
    conn = %{conn | params: %{}, path_params: %{"uuid" => uuid}}

    conn =
      conn
      |> assign(:locale, "en")
      |> assign(:base_url, "http://www.example.com")
      |> assign(:current_user, nil)
      |> assign(:self_hosted, true)
      |> assign(:now, DateTime.utc_now())
      |> DawarichWeb.NativePublicPage.call(:digest)

    assert conn.status == 200
    text = LazyHTML.from_document(conn.resp_body) |> LazyHTML.text()
    assert text =~ ~r/61\s+cities/
    assert text =~ ~r/\+56\s+more/
    assert text =~ "City 5"
    refute text =~ "City 6"
  end

  test "public HTTP expiry uses the signed viewer timezone instead of the owner or anonymous zone" do
    user =
      RailsUser.insert!(%{
        id: 19003,
        email: "native-public-zone@example.invalid",
        settings: %{"timezone" => "Pacific/Pago_Pago"}
      })

    uuid = Ecto.UUID.generate()

    StatsSeeds.digest!(user.id, %{
      year: 2024,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: %{
        "enabled" => true,
        "expiration" => "1h",
        "expires_at" => "2026-10-07 02:00:00"
      }
    })

    conn = build_conn("GET", "/shared/digest/" <> uuid)
    conn = %{conn | params: %{}, path_params: %{"uuid" => uuid}}

    conn =
      conn
      |> assign(:locale, "en")
      |> assign(:base_url, "http://www.example.com")
      |> assign(:self_hosted, true)
      |> assign(:now, ~U[2026-10-07 12:00:00Z])

    assert (conn
            |> assign(:current_user, user)
            |> DawarichWeb.NativePublicPage.call(:digest)).status == 200

    assert (conn
            |> assign(:current_user, nil)
            |> DawarichWeb.NativePublicPage.call(:digest)).status == 302
  end

  test "native mixed public content preserves a caller-owned map slot and bounded day navigation" do
    html =
      apply(DawarichWeb.NativePublicContent, :resource, [
        %{
          __changed__: nil,
          locale: "de",
          link: %{id: "synthetic-share", type: "trip", name: "Synthetic", settings: %{}},
          resource: %{
            name: "Synthetic",
            started_at: ~N[2026-01-01 00:00:00],
            ended_at: ~N[2026-02-05 00:00:00],
            unit: "mi",
            track_duration: 3600,
            speed: 12.0,
            gain: 50,
            loss: 20,
            mode: 2,
            duration: %{hours: 1},
            distance: 1609.344,
            countries: ["Germany"],
            description: "<p>Sanitized description</p>",
            days: [%{date: ~D[2026-01-01], note: "Plain <script> note", stats: nil}],
            photos: [],
            next_cursor: "2026-02-01"
          },
          map: [
            %{inner_block: fn _, _ -> Phoenix.HTML.raw("<div id='caller-native-map'></div>") end}
          ]
        }
      ])
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "caller-native-map"
    assert html =~ "1,0 mi"
    assert html =~ "50"
    assert html =~ "Germany"
    assert html =~ "Sanitized description"
    assert html =~ "Plain &lt;script&gt; note"
    assert html =~ "cursor=2026-02-01"
    refute html =~ "RailsStimulus"
    refute html =~ "data-controller="
  end

  test "native public month retains peak activity places flight distance and kilometre chart with caller map" do
    page = %{
      stat: %{
        year: 2024,
        month: 3,
        distance: 1609.344,
        flight_distance: 3218.688,
        daily: [[1, 1000], [2, 2000]],
        toponyms: [%{"country" => "Germany", "cities" => [%{"city" => "Berlin"}]}]
      },
      unit: "mi"
    }

    html =
      DawarichWeb.NativePublicContent.month(%{
        __changed__: nil,
        locale: "en",
        page: page,
        map: [
          %{inner_block: fn _, _ -> Phoenix.HTML.raw("<div id='native-month-map'></div>") end}
        ]
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "native-month-map"
    assert html =~ "Germany"
    assert html =~ "Berlin"
    assert html =~ DawarichWeb.StatsFormat.distance("en", 3218.688, "mi")
    assert html =~ DawarichWeb.StatsFormat.peak_text("en", 2024, 3, {2, 2000}, "mi")

    [chart] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-chart]")
      |> LazyHTML.attribute("data-chart")

    assert Jason.decode!(chart)["data"] == [[1, 1], [2, 2]]
    refute html =~ "data-controller="
  end

  test "native phrase prompt is labelled preserves HTTP unlock and never echoes a submitted phrase" do
    html =
      apply(DawarichWeb.NativePublicContent, :prompt, [
        %{
          __changed__: nil,
          locale: "de",
          link: %{id: "synthetic-share"},
          error: "Generic refusal",
          rails_session: %{"_csrf_token" => DawarichWeb.RailsCsrf.new_token()}
        }
      ])
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    doc = LazyHTML.from_fragment(html)
    assert html =~ "/s/synthetic-share/unlock"
    assert html =~ "Generic refusal"
    assert Enum.count(LazyHTML.query(doc, "label[for=public-phrase]")) == 1
    assert LazyHTML.query(doc, "input[name=phrase]") |> LazyHTML.attribute("value") == []
    assert Enum.count(LazyHTML.query(doc, "input[name=authenticity_token]")) == 1
    refute html =~ "data-disable-with"
  end
end
