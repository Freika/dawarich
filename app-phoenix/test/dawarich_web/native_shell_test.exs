defmodule DawarichWeb.NativeShellTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1, render_component: 2]
  import Plug.Conn
  import Plug.Test

  alias Dawarich.{RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{Chrome, CoreComponents, RailsCsrf}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = Dawarich.Accounts.get(FrameSeeds.user!(8392).id)
    %{user: user}
  end

  defp navbar(user, extra \\ %{}) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        current_user: user,
        data: Dawarich.Navbar.load(user, now: now, self_hosted: true),
        locale: "en",
        request_path: "/tags",
        base_url: "http://localhost",
        self_hosted: true,
        rails_csrf_token: "token",
        now: now,
        native: true
      },
      extra
    )
    |> DawarichWeb.Navbar.navbar()
    |> rendered_to_string()
  end

  defp doc(html), do: LazyHTML.from_document(html)
  defp query(html, selector), do: html |> doc() |> LazyHTML.query(selector)

  test "the native navbar signs out with a plain form the sign-out handler accepts", %{user: user} do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    session = RailsUser.session(user.id)
    html = navbar(user, %{rails_csrf_token: RailsCsrf.masked_token(session)})

    forms = query(html, "form[action='/users/sign_out']")
    assert forms |> LazyHTML.attribute("method") |> Enum.uniq() == ["post"]

    body =
      forms
      |> Enum.at(0)
      |> LazyHTML.query("input[type=hidden]")
      |> Enum.map(&{hd(LazyHTML.attribute(&1, "name")), hd(LazyHTML.attribute(&1, "value"))})
      |> URI.encode_query()

    conn =
      conn(:post, "/users/sign_out", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> put_req_header("cookie", "_dawarich_session=#{RailsUser.cookie(session)}")
      |> DawarichWeb.AuthHandler.call(
        enabled: true,
        registration_enabled: false,
        fallback: &put_private(&1, :handed_to_rails, true)
      )

    refute conn.private[:handed_to_rails]
    assert conn.status in [302, 303]

    {:ok, after_sign_out} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    refute Map.has_key?(after_sign_out, "warden.user.user.key")
  end

  test "the native navbar uses no Turbo or Stimulus attributes for links and consent", %{
    user: user
  } do
    html = navbar(user)

    assert query(html, "a[data-method], a[data-turbo], form[data-turbo-stream]") |> Enum.empty?()
    assert query(html, "a[href^='/settings/theme?theme=']") |> Enum.count() >= 1
  end

  test "notice flashes time out and error flashes stay until closed" do
    notice =
      render_component(&Chrome.flash/1, locale: "en", flash: %{"notice" => "Saved"}, native: true)

    error =
      render_component(&Chrome.flash/1, locale: "en", flash: %{"error" => "Failed"}, native: true)

    assert notice =~ "Saved"
    assert notice =~ "dawarich:flash-timeout"
    refute error =~ "dawarich:flash-timeout"
    refute notice =~ "data-controller"
    refute notice =~ "data-action"
    assert query(notice, "#flash-messages [role=alert] button[phx-click]") |> Enum.count() == 1
  end

  test "the hybrid flash keeps its current markup" do
    hybrid = render_component(&Chrome.flash/1, locale: "en", flash: %{"notice" => "Saved"})
    assert hybrid =~ ~s(data-controller="removals")
  end

  test "core input renders its label, value and every error" do
    form =
      Phoenix.Component.to_form(%{"name" => "Home"},
        as: :tag,
        errors: [name: {"is bad", []}, name: {"is taken", []}]
      )

    html = render_component(&CoreComponents.input/1, field: form[:name], label: "Name")

    assert query(html, "label") |> LazyHTML.text() =~ "Name"
    assert query(html, "input[name='tag[name]']") |> LazyHTML.attribute("value") == ["Home"]
    assert html =~ "is bad"
    assert html =~ "is taken"
  end

  test "core button forwards phx-disable-with" do
    html =
      render_component(&CoreComponents.button/1, inner_block: [], "phx-disable-with": "Saving…")

    assert html =~ ~s(phx-disable-with="Saving…")
  end
end
