defmodule DawarichWeb.TrialResumeTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.{RailsAuth, RequireUser, TrialGate, TrialResumeHeaders, TrialResumeStatus}
  alias DawarichWeb.TrialLive.Resume

  @now ~U[2026-10-03 10:00:00Z]
  @jti "00000000-0000-4000-8000-000000010001"

  @tag a10_boundary: :resume_headers
  test "resume pipeline preserves no-store and no-cache before auth" do
    for {id, name} <- [{nil, "resume_guest"}, {10001, "resume_cloud_active"}] do
      Repo.query!("UPDATE users SET status = 1 WHERE id = 10001", [], log: false)
      conn = if id, do: RailsUser.signed_in(id), else: Phoenix.ConnTest.build_conn()
      conn = Phoenix.ConnTest.dispatch(conn, DawarichWeb.Endpoint, :get, "/trial/resume", nil)
      state = fixture(name)
      assert conn.status == state["status"]
      assert conn.resp_body == ""

      for header <- ~w(cache-control pragma location),
          do: assert(get_resp_header(conn, header) == List.wrap(state["headers"][header]))
    end
  end

  @tag a10_boundary: :resume_mount
  test "pending resume GET mounts the Rails checkout page" do
    conn =
      Phoenix.ConnTest.dispatch(
        RailsUser.signed_in(10001),
        DawarichWeb.Endpoint,
        :get,
        "/trial/resume",
        nil
      )

    assert conn.status == 200
    doc = LazyHTML.from_document(conn.resp_body)

    [location] =
      doc |> LazyHTML.query(".hero a[data-turbo='false']") |> LazyHTML.attribute("href")

    token = URI.decode_query(URI.parse(location).query)["token"]
    [_, payload, _] = String.split(token, ".")
    claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert claims["variant"] == "reverse_trial"

    assert ParityHTML.fragment(String.replace(conn.resp_body, token, "TOKEN"), ".hero") ==
             ParityHTML.normalize(
               File.read!("test/fixtures/trial_home/resume_cloud_pending.html")
             )

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    keys = ~w(SELF_HOSTED MANAGER_URL JWT_SECRET_KEY)
    previous = Map.new(keys, &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "false")
    System.put_env("MANAGER_URL", "https://manager.example.test")
    System.put_env("JWT_SECRET_KEY", "a10-checkout-synthetic-signing-phrase-not-for-production")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    RailsUser.insert!(%{
      id: 10001,
      email: "a10-checkout@example.invalid",
      status: 3,
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    :ok
  end

  @tag a10_resume: :headers
  test "resume header and status plugs preserve direct response contracts" do
    pending =
      prepared()
      |> TrialResumeHeaders.call([])
      |> RequireUser.call([])
      |> TrialResumeStatus.call([])

    assert pending.state != :sent
    assert get_resp_header(pending, "cache-control") == ["no-store"]
    assert get_resp_header(pending, "pragma") == ["no-cache"]

    active =
      pending
      |> assign(:current_user, %{pending.assigns.current_user | status: 1})
      |> TrialResumeStatus.call([])

    assert active.status == 302
    assert active.resp_body == ""
    assert get_resp_header(active, "location") == ["http://www.example.com/"]
    assert get_resp_header(active, "cache-control") == ["no-store"]
    guest = Plug.Test.conn(:get, "/trial/resume") |> RailsAuth.call([]) |> assign(:locale, "en")
    guest = guest |> TrialResumeHeaders.call([]) |> RequireUser.call([])
    assert get_resp_header(guest, "cache-control") == ["no-cache"]
    assert get_resp_header(guest, "pragma") == []
    System.delete_env("JWT_SECRET_KEY")
    assert true == TrialGate.resume?(Plug.Test.conn(:get, "/trial/resume"), %{})
    Repo.query!("UPDATE users SET status = 1 WHERE id = 10001", [], log: false)
    assert true == TrialGate.resume?(prepared(), %{})
    Repo.query!("UPDATE users SET status = 3 WHERE id = 10001", [], log: false)
    assert false == TrialGate.resume?(prepared(), %{})
  end

  @tag a10_resume: :page
  test "pending resume has reverse-trial checkout link and Rails account deletion action" do
    for mode <- ~w(cloud self_hosted) do
      System.put_env("SELF_HOSTED", if(mode == "cloud", do: "false", else: "true"))
      context = %{current_user: Accounts.get(10001), locale: "en"}
      page = Resume.page(context, now: @now, jti: @jti)
      html = render_component(&Resume.render/1, Map.merge(context, page))
      state = fixture("resume_#{mode}_pending")
      doc = LazyHTML.from_fragment(html)
      [location] = doc |> LazyHTML.query("a[data-turbo='false']") |> LazyHTML.attribute("href")
      token = URI.decode_query(URI.parse(location).query)["token"]
      [header, payload, signature] = String.split(token, ".")
      assert Base.url_decode64!(header, padding: false) == state["jwt"]["header_json"]
      assert Base.url_decode64!(payload, padding: false) == state["jwt"]["payload_json"]

      assert Base.encode16(Base.url_decode64!(signature, padding: false), case: :lower) ==
               state["jwt"]["signature_hex"]

      rails = File.read!("test/fixtures/trial_home/resume_#{mode}_pending.html")

      assert ParityHTML.normalize(String.replace(html, token, "TOKEN")) ==
               ParityHTML.normalize(rails)

      assert ParityHTML.stimulus(html, "a") == ParityHTML.stimulus(rails, "a")

      session =
        DawarichWeb.RailsAuth.live_session(%{
          prepared()
          | assigns: Map.merge(prepared().assigns, page)
        })

      assert false == String.contains?(Jason.encode!(session), token)
    end
  end

  defp prepared do
    Plug.Test.conn(:get, "/trial/resume")
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(RailsUser.session(10001)))
    |> RailsAuth.call([])
    |> assign(:locale, "en")
  end

  defp fixture(name), do: Jason.decode!(File.read!("test/fixtures/trial_home/#{name}.json"))
end
