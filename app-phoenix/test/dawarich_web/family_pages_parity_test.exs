defmodule DawarichWeb.FamilyPagesParityTest do
  use Dawarich.JobsCase, async: false

  import Plug.Conn
  alias Dawarich.{FamilyPage, Repo}
  alias Dawarich.Test.{FrameSeeds, MapStimulus, ParityHTML}
  alias DawarichWeb.{FamilyGate, FamilyInvitationPage, RequireUser}

  @dir "test/fixtures/family_pages"
  @cases ~w(guest no_family new_self_hosted owner member owner_new_redirect edit_owner edit_member
             invitations_owner invitations_member consented_map invitation_pending invitation_equal
             invitation_past invitation_accepted invitation_cancelled invitation_expired invitation_missing
             invitation_wrong_email invitation_matching_email invitation_nested_alias request_target
             request_foreign_target request_missing request_expired request_no_family new_entitled new_upgrade
             creator_subscription_future creator_subscription_equal creator_subscription_past access_until_future
             access_until_equal access_until_past subscribed_owner_expired_access lapsed_owner lapsed_member
             lapsed_invitations lapsed_invitation lapsed_request paid_downgrade non_family_renewal)
  @names for name <- @cases, locale <- ~w(en de es fr pl ca zh), do: name <> "_" <> locale

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    saved = Map.new(~w(SELF_HOSTED JWT_SECRET_KEY MANAGER_URL), &{&1, System.get_env(&1)})
    System.put_env("JWT_SECRET_KEY", "a9fpl-fixture-jwt-not-for-production")
    System.put_env("MANAGER_URL", "https://manager.a9fpl.dawarich.test")

    on_exit(fn ->
      for {name, value} <- saved,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)
  end

  test "corpus is complete" do
    actual =
      @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".json"))

    assert Enum.sort(actual) == Enum.sort(@names)
    assert length(@names) == 294
  end

  test "Rails sharing response can replace native toggle and getting started slots" do
    state = FrameSeeds.load_family("owner_en")
    user = FrameSeeds.seed_family!(state)
    now = DateTime.from_iso8601(state["now"]) |> elem(1)
    {:html, native} = response(conn(state, user, now), state, user, now)

    native =
      DawarichWeb.Layouts.app(%{
        __changed__: nil,
        inner_content: Phoenix.HTML.raw(native),
        current_user: user,
        navbar: Dawarich.Navbar.load(user, now: now, self_hosted: true),
        locale: "en",
        request_path: "/family",
        base_url: "http://www.example.com",
        self_hosted: true,
        rails_csrf_token: "CSRF",
        now: now,
        suggested_locale: nil,
        flash: %{},
        flash_messages: []
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    for locale <- ~w(en de es fr pl ca zh) do
      rails = File.read!(Path.join(@dir, "sharing_toggle_#{locale}.stream.html"))

      streams =
        rails |> LazyHTML.from_fragment() |> LazyHTML.query("turbo-stream[action='replace']")

      for target <- ~w(location-sharing-90101 family-navbar-indicator family-getting-started-slot) do
        assert Enum.any?(LazyHTML.query(native |> LazyHTML.from_fragment(), "##{target}"))
        assert target in LazyHTML.attribute(streams, "target")

        [_, template] =
          Regex.run(
            ~r{<turbo-stream[^>]*target="#{target}"[^>]*>\s*<template>(.*?)</template>}s,
            rails
          )

        assert Enum.any?(LazyHTML.query(LazyHTML.from_fragment(template), "##{target}"))
      end

      [_, template] =
        Regex.run(
          ~r{<turbo-stream[^>]*target="location-sharing-90101"[^>]*>\s*<template>(.*?)</template>}s,
          rails
        )

      assert Enum.any?(
               LazyHTML.query(
                 LazyHTML.from_fragment(template),
                 "form[action='/family/location_sharing'] input[name='_method'][value='patch']"
               )
             )
    end
  end

  for name <- @names do
    @name name
    @tag family_case: name
    test "family GET corpus #{@name} matches Rails in all shipped locales outside registered hydration fields" do
      state = FrameSeeds.load_family(@name)
      user = FrameSeeds.seed_family!(state)
      now = DateTime.from_iso8601(state["now"]) |> elem(1)
      System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))
      conn = conn(state, user, now)

      case response(conn, state, user, now) do
        {:html, html} ->
          assert state["status"] == 200
          rails = File.read!(Path.join(@dir, @name <> ".html"))
          native = normalize(html)
          expected = normalize(rails)
          assert native == expected, ParityHTML.first_difference(native, expected)

          assert attributes(html) == attributes(rails),
                 ParityHTML.first_difference(attributes(html), attributes(rails))

        {:redirect, conn} ->
          assert conn.status == state["status"]
          assert get_resp_header(conn, "location") == [state["location"]]

          assert get_resp_header(conn, "content-type") == [
                   state["content_type"] <> "; charset=utf-8"
                 ]

          changes = conn.private[:dawarich_rails_session_changes] || %{}
          assert (get_in(changes, ["flash", "flashes"]) || %{}) == state["flash"]
          assert changes["user_return_to"] == state["session"]["user_return_to"]

        {:error, status} ->
          assert state["status"] == status
      end
    end
  end

  defp conn(state, user, now) do
    Plug.Test.conn("GET", state["path"])
    |> Map.put(:host, "www.example.com")
    |> fetch_query_params()
    |> assign(:current_user, user)
    |> assign(:locale, state["locale"])
    |> assign(:suggested_locale, nil)
    |> assign(:rails_session, %{})
    |> DawarichWeb.LayoutAssigns.call([])
    |> assign(:now, now)
    |> assign(:self_hosted, state["self_hosted"])
  end

  defp response(conn, state, user, now) do
    path = conn.request_path

    if String.starts_with?(path, "/invitations/") or Regex.match?(~r{^/family/invitations/}, path) do
      token = path |> String.split("/") |> List.last()
      result = FamilyInvitationPage.read(token, user, now: now, self_hosted: state["self_hosted"])
      conn = FamilyInvitationPage.respond(conn, result)

      if conn.status == 200 do
        assert get_resp_header(conn, "content-type") == [
                 state["content_type"] <> "; charset=utf-8"
               ]

        assert [state["title"]] ==
                 conn.resp_body
                 |> LazyHTML.from_document()
                 |> LazyHTML.query("title")
                 |> LazyHTML.text()
                 |> List.wrap()

        {:html,
         conn.resp_body
         |> LazyHTML.from_document()
         |> LazyHTML.query("body > div.container > div.w-full > div.flex > *")
         |> LazyHTML.to_html()}
      else
        {:redirect, conn}
      end
    else
      conn = RequireUser.call(conn, [])

      if conn.halted do
        {:redirect, conn}
      else
        conn = FamilyGate.call(conn, [])

        if conn.halted do
          {:redirect, conn}
        else
          render_family(conn, state, user, now)
        end
      end
    end
  rescue
    error in DawarichWeb.NotFoundError -> {:error, error.plug_status}
  end

  defp render_family(conn, state, user, now) do
    action =
      case conn.request_path do
        "/family" -> :show
        "/family/new" -> :new
        "/family/edit" -> :edit
        "/family/invitations" -> :invitations
        "/family/location_requests/" <> id -> {:request, String.to_integer(id)}
      end

    {:ok, page} = FamilyPage.read(user, action, now: now, self_hosted: state["self_hosted"])

    assigns = %{
      page: page,
      locale: state["locale"],
      now: now,
      rails_csrf_token: "CSRF",
      base_url: "http://www.example.com",
      self_hosted: state["self_hosted"]
    }

    case page.state do
      :show ->
        {:html, html(&DawarichWeb.FamiliesLive.Show.render/1, assigns) |> inner("#family-shell")}

      :invitations ->
        {:html, html(&DawarichWeb.FamilyInvitations.invitation_index/1, assigns)}

      :request ->
        {:html, html(&DawarichWeb.FamilyRequestForms.location_request/1, assigns)}

      _ ->
        content = if page.state == :lapsed, do: "renew_family", else: "create_family"

        href =
          Dawarich.SubscriptionToken.url(user, now, plan: "family", interval: "annual") <>
            "&" <>
            DawarichWeb.Params.to_query(%{
              "utm_source" => "app",
              "utm_medium" => "family",
              "utm_campaign" => "family_upgrade",
              "utm_content" => content
            })

        {:html,
         html(&DawarichWeb.FamiliesLive.Form.render/1, Map.put(assigns, :upgrade_href, href))
         |> inner("#family-form-shell")}
    end
  end

  defp html(fun, assigns),
    do:
      fun.(Map.put(assigns, :__changed__, nil))
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

  defp inner(html, selector),
    do:
      html |> LazyHTML.from_fragment() |> LazyHTML.query(selector <> " > *") |> LazyHTML.to_html()

  defp normalize(html), do: html |> hydration_tree() |> ParityHTML.normalize()

  defp attributes(html),
    do:
      html
      |> hydration_tree()
      |> LazyHTML.from_tree()
      |> LazyHTML.to_html()
      |> then(
        &MapStimulus.attributes("<div id=family-parity>" <> &1 <> "</div>", ["#family-parity"])
      )

  defp hydration_tree(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Enum.flat_map(&hydration/1)

  defp hydration({tag, attrs, children}) do
    data = Map.new(attrs)

    cond do
      Map.has_key?(data, "data-family-last-seen") or
          (tag == "span" and data["class"] == "text-xs text-base-content/40" and
             Enum.any?(children, &(is_binary(&1) and String.starts_with?(String.trim(&1), "·")))) ->
        []

      data["data-family-map-target"] == "map" ->
        [{tag, attrs, []}]

      true ->
        attrs =
          Enum.reject(attrs, fn {key, _} ->
            key in ~w(data-family-member-id data-family-time-ago data-lat data-lon) or
              (key == "id" and data["data-controller"] == "family-map") or
              (key == "data-action" and data[key] == "click->family-map#flyToMember")
          end)

        attrs =
          Enum.map(attrs, fn {key, value} ->
            cond do
              key == "data-family-map-locations-value" ->
                {key, "[]"}

              key == "class" and (data["data-lat"] != nil or data["data-family-member-id"] != nil) ->
                {key,
                 value
                 |> String.split()
                 |> Enum.reject(&(&1 == "cursor-pointer"))
                 |> Enum.join(" ")}

              true ->
                {key, value}
            end
          end)

        [{tag, attrs, Enum.flat_map(children, &hydration/1)}]
    end
  end

  defp hydration(other), do: [other]
end
