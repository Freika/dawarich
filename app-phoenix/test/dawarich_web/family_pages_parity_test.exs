defmodule DawarichWeb.FamilyPagesParityTest do
  use Dawarich.JobsCase, async: false

  import Plug.Conn
  alias Dawarich.{FamilyPage, Repo}
  alias Dawarich.Test.FrameSeeds
  alias DawarichWeb.{FamilyInvitationPage, RequireUser}

  @dir "test/fixtures/family_pages"
  @cases ~w(owner_alone guest no_family new_self_hosted owner member owner_new_redirect edit_owner edit_member
             invitations_owner invitations_member consented_map invitation_pending invitation_equal
             invitation_past invitation_accepted invitation_cancelled invitation_expired invitation_missing
             invitation_wrong_email invitation_matching_email invitation_nested_alias request_target
             request_foreign_target request_missing request_expired request_no_family new_entitled new_upgrade
             creator_subscription_future creator_subscription_equal creator_subscription_past access_until_future
             access_until_equal access_until_past subscribed_owner_expired_access lapsed_owner lapsed_member
             lapsed_invitations lapsed_invitation lapsed_request paid_downgrade non_family_renewal)
  @names for name <- @cases, locale <- ~w(en de es fr pl ca zh), do: name <> "_" <> locale

  setup do
    Code.ensure_loaded!(Dawarich.Accounts.User)
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
    assert length(@names) == 301
  end

  for name <- @names do
    @name name
    @tag family_case: name
    test "family GET corpus #{@name} preserves scoped state and visible inputs in all shipped locales" do
      state = FrameSeeds.load_family(@name)
      user = FrameSeeds.seed_family!(state)
      now = DateTime.from_iso8601(state["now"]) |> elem(1)
      System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))
      conn = conn(state, user, now)

      case response(conn, state, user, now) do
        {:html, html} ->
          assert state["status"] == 200
          rails = File.read!(Path.join(@dir, @name <> ".html"))

          rails =
            if String.starts_with?(@name, "owner_alone_"),
              do:
                String.replace(
                  rails,
                  ~s(id="family_invitation_email"),
                  ~s(id="native-family-onboarding-email"),
                  global: false
                ),
              else: rails

          if String.starts_with?(state["path"], "/family?") do
            rails_shell = File.read!(Path.join(@dir, @name <> ".shell.html"))

            assert shell(html) == shell(rails_shell),
                   Dawarich.Test.ParityHTML.first_difference(shell(html), shell(rails_shell))
          end

          if not invitation_path?(state["path"]) do
            selector =
              if String.starts_with?(state["path"], "/family?"),
                do: "#native-family-page",
                else: ".container"

            actual =
              html
              |> LazyHTML.from_fragment()
              |> LazyHTML.query(selector)
              |> LazyHTML.to_tree()
              |> presentation(state)

            expected =
              rails |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> presentation(state)

            assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
          end

          if invitation_path?(state["path"]) do
            assert invitation_projection(html) == invitation_projection(rails)
          else
            doc = LazyHTML.from_fragment(html)
            expected = LazyHTML.from_fragment(rails)

            assert visible_text(
                     LazyHTML.query(
                       doc,
                       if(String.starts_with?(state["path"], "/family/location_requests/"),
                         do: "h2",
                         else: "h1"
                       )
                     )
                     |> LazyHTML.to_tree()
                   ) ==
                     visible_text(
                       LazyHTML.query(
                         expected,
                         if(String.starts_with?(state["path"], "/family/location_requests/"),
                           do: "h2",
                           else: "h1"
                         )
                       )
                       |> LazyHTML.to_tree()
                     )

            assert input_projection(doc) == input_projection(expected)
            refute html =~ "data-controller="
            refute html =~ "data-turbo-method"
            refute html =~ "a9fpl-pending"
          end

        {:redirect, conn} ->
          assert conn.status == state["status"]
          assert get_resp_header(conn, "location") == [state["location"]]

          assert get_resp_header(conn, "content-type") == [
                   state["content_type"] <> "; charset=utf-8"
                 ]

          changes = conn.private[:dawarich_rails_session_changes] || %{}
          assert (get_in(changes, ["flash", "flashes"]) || %{}) == state["flash"]
          assert changes["user_return_to"] == state["session"]["user_return_to"]

        {:family_refused, reason} ->
          assert reason in [
                   nil,
                   :feature_unavailable,
                   :not_in_family,
                   :not_authorized,
                   :not_request_target
                 ]

          assert state["status"] in [302, 303]

        {:error, status} ->
          assert state["status"] == status
      end
    end
  end

  defp shell(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> shell_content()
    |> LazyHTML.from_tree()
    |> LazyHTML.to_html()
    |> Dawarich.Test.LayoutFixtures.region(".container")
  end

  defp shell_content(nodes) when is_list(nodes), do: Enum.map(nodes, &shell_content/1)

  defp shell_content({tag, attrs, children}) do
    if Map.new(attrs)["class"] == "flex w-full min-w-0 gap-5",
      do: {tag, attrs, [{"native-family-content", [], []}]},
      else: {tag, attrs, shell_content(children)}
  end

  defp shell_content(other), do: other

  defp presentation(nodes, state) do
    nodes |> contract_nodes(state) |> Dawarich.Test.ParityHTML.normalize()
  end

  defp contract_nodes(nodes, state) when is_list(nodes),
    do: Enum.map(nodes, &contract_nodes(&1, state))

  defp contract_nodes({tag, attrs, children}, state) do
    data = Map.new(attrs)
    attrs = mobile_actions(attrs, tag, state)

    cond do
      data["id"] == "native-family-map" or data["data-family-map-target"] == "map" ->
        {"native-map-insertion", [], []}

      data["class"] == "text-xs text-base-content/50 font-mono break-all select-all mt-1" ->
        {tag, attrs, ["invitation capability revealed over admitted HTTP"]}

      true ->
        attrs =
          Enum.map(attrs, fn
            {"href", "https://manager." <> _} ->
              {"href", "/native/family/upgrade"}

            {"href", "/invitations/" <> token} ->
              {"href", invitation_view(state, token)}

            {"href", "/family/invitations/" <> _} ->
              {"href", "#"}

            {"href", "/family/members/" <> _} ->
              {"href", "#"}

            {"href", "/family"} = attr ->
              if(data["data-turbo-method"] == "delete", do: {"href", "#"}, else: attr)

            {"action", "/family/invitations/" <> _} ->
              {"action", "invitation-cancel"}

            {"action", "/native/family/invitations/" <> _} ->
              {"action", "invitation-cancel"}

            attr ->
              attr
          end)

        attrs =
          Enum.reject(attrs, fn {name, _} ->
            name in ~w(data-lon data-lat data-request-status) or
              (name == "onclick" and
                 data["onclick"] ==
                   "document.getElementById('invite-section').scrollIntoView({behavior:'smooth'})") or
              (name == "aria-label" and tag == "button" and
                 (data["phx-hook"] == "FamilyInvitationClipboard" or
                    data["data-native-family-action"] == "cancel_invitation"))
          end)

        {tag, attrs, contract_nodes(children, state)}
    end
  end

  defp contract_nodes(other, _), do: other

  defp mobile_actions(attrs, tag, state) do
    if URI.parse(state["path"]).path in ["/family/edit", "/family/invitations"] do
      classes = %{
        "flex items-center justify-between mb-6" =>
          "flex flex-wrap items-center justify-between gap-2 mb-6",
        "flex items-center justify-between pt-4" =>
          "flex flex-wrap items-center justify-between gap-3 pt-4",
        "flex space-x-3" => "flex flex-wrap gap-3",
        "flex items-center justify-between p-4 bg-base-100 rounded-lg" =>
          "flex flex-wrap items-center justify-between gap-3 p-4 bg-base-100 rounded-lg",
        "flex space-x-2" => "flex flex-wrap gap-2"
      }

      attrs
      |> Enum.reject(&(&1 == {"class", "min-w-0 [overflow-wrap:anywhere]"}))
      |> Enum.map(fn
        {"class", "text-sm text-base-content"} when tag == "dd" ->
          {"class", "text-sm text-base-content [overflow-wrap:anywhere]"}

        {"class", value} ->
          {"class", Map.get(classes, value, value)}

        attr ->
          attr
      end)
    else
      attrs
    end
  end

  defp invitation_view(state, token) do
    row = Enum.find(state["rows"]["family_invitations"], &(&1["token"] == token))
    "/native/family/invitations/#{row["id"]}/view"
  end

  defp invitation_path?(path),
    do:
      String.starts_with?(path, "/invitations/") or
        String.starts_with?(path, "/family/invitations/")

  defp invitation_projection(html) do
    doc = LazyHTML.from_fragment(html)
    text = doc |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()

    links =
      for {"a", attrs, children} <- doc |> LazyHTML.query("a") |> LazyHTML.to_tree() do
        data = Map.new(attrs)
        {data["data-method"] || "get", data["href"], visible_text(children)}
      end

    forms =
      for {"form", attrs, children} <- doc |> LazyHTML.query("form") |> LazyHTML.to_tree() do
        data = Map.new(attrs)
        form = LazyHTML.from_tree(children)

        inputs =
          for {"input", attrs, _} <- form |> LazyHTML.query("input") |> LazyHTML.to_tree(),
              data = Map.new(attrs),
              into: %{},
              do: {data["name"], data["value"]}

        assert is_binary(inputs["authenticity_token"])
        assert inputs["authenticity_token"] != ""
        assert data["method"] == "post"
        method = inputs["_method"] || "post"
        path = data["action"]

        path =
          if inputs["token"],
            do: path <> "?token=" <> URI.encode_www_form(inputs["token"]),
            else: path

        button = form |> LazyHTML.query("button[type=submit]") |> LazyHTML.to_tree()
        assert length(button) == 1
        {method, path, visible_text(button)}
      end

    {text, Enum.sort(links ++ forms)}
  end

  defp visible_text(nodes),
    do:
      nodes
      |> LazyHTML.from_tree()
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

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
        action =
          case conn.request_path do
            "/family" -> :show
            "/family/new" -> :new
            "/family/edit" -> :edit
            "/family/invitations" -> :invitations
            "/family/location_requests/" <> id -> {:request, String.to_integer(id)}
          end

        case FamilyPage.read(user, action, now: now, self_hosted: state["self_hosted"]) do
          {:redirect, path, reason} ->
            expected = if reason == :feature_unavailable, do: :expired, else: :unauthorized

            assert {:error, ^expected} =
                     Dawarich.Families.page(
                       Dawarich.Accounts.Scope.for_user(user, state["locale"]),
                       action,
                       now: now,
                       self_hosted: state["self_hosted"]
                     )

            assert state["location"] == "http://www.example.com" <> path
            {:family_refused, reason}

          {:error, status} ->
            {:error, status}

          {:ok, _} ->
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

    scope = Dawarich.Accounts.Scope.for_user(user, state["locale"])

    {:ok, safe} =
      Dawarich.Families.page(scope, action, now: now, self_hosted: state["self_hosted"])

    assert safe ==
             Map.put(
               page,
               :invitations,
               Enum.map(page[:invitations] || [], &Map.delete(&1, :token))
             )

    assigns = %{
      page: safe,
      locale: state["locale"],
      now: now,
      current_scope: scope,
      rails_csrf_token: "CSRF",
      base_url: "http://www.example.com",
      self_hosted: state["self_hosted"],
      errors: [],
      confirmation: nil,
      family_name: get_in(page, [:family, :name]) || "",
      invitation_email: ""
    }

    assigns =
      if page.state == :show do
        {:ok, map_page} =
          Dawarich.Maps.Family.view(scope, now: now, self_hosted: state["self_hosted"])

        Map.merge(assigns, %{
          page: map_page,
          map_error: nil,
          current_user: user,
          navbar: Dawarich.Navbar.load(user, now: now, self_hosted: state["self_hosted"]),
          suggested_locale: nil,
          query_params: %{},
          flash_messages: [],
          native: true,
          flash: %{},
          request_path: "/family"
        })
      else
        assigns
      end

    fun =
      case page.state do
        :show -> &DawarichWeb.NativeFamilyPage.page/1
        :invitations -> &DawarichWeb.FamiliesLive.Invitations.render/1
        :request -> &DawarichWeb.FamiliesLive.LocationRequest.render/1
        _ -> &DawarichWeb.FamiliesLive.Form.render/1
      end

    {:html, html(fun, assigns)}
  end

  defp input_projection(doc) do
    values =
      for {"input", attrs, _} <- doc |> LazyHTML.query("input") |> LazyHTML.to_tree(),
          data = Map.new(attrs),
          data["type"] not in ~w(hidden submit),
          do:
            {data["type"], if(data["type"] == "checkbox", do: "", else: data["value"] || ""),
             Map.has_key?(data, "checked")}

    selects =
      for {"select", attrs, children} <- doc |> LazyHTML.query("select") |> LazyHTML.to_tree(),
          _data = Map.new(attrs),
          do:
            {"select",
             for(
               {"option", attrs, _} <-
                 LazyHTML.from_tree(children) |> LazyHTML.query("option") |> LazyHTML.to_tree(),
               data = Map.new(attrs),
               do: {data["value"], Map.has_key?(data, "selected")}
             )}

    Enum.sort(values ++ selects)
  end

  defp html(fun, assigns),
    do:
      fun.(Map.put(assigns, :__changed__, nil))
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
end
