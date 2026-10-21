defmodule DawarichWeb.ShareManagementParityTest do
  use Dawarich.IngestCase, async: false
  require Phoenix.LiveViewTest
  alias Dawarich.{Sharing, Repo}
  alias Dawarich.Test.FrameSeeds

  @dir "test/fixtures/share_management"
  @cases ~w(ambiguous_override hub_active_live hub_active_shared hub_active_timeline hub_active_unknown
    hub_bad_range hub_empty_live hub_empty_make hub_empty_shared hub_empty_timeline hub_empty_unknown
    hub_guest hub_range live_active live_active_frame live_delete live_delete_missing
    live_expiry_America_Havana live_expiry_Asia_Tokyo live_expiry_Europe_Berlin live_expiry_UTC
    live_expiry_blank live_expiry_dst_after live_expiry_future live_expiry_malformed live_expiry_past
    live_hub_blank live_hub_false live_hub_true live_invalid_frame live_invalid_hub live_invalid_magic_phrase
    live_invalid_name live_json_create live_new_document live_new_frame live_phrase live_phrase_missing
    live_revoke live_revoke_missing live_settings live_turbo_create live_url live_url_missing
    shared_revoke_foreign shared_revoke_live shared_revoke_missing shared_revoke_timeline shared_revoke_track
    shared_revoke_trip trip_active trip_active_frame trip_delete trip_delete_missing trip_expiry_blank
    trip_expiry_dst_after trip_expiry_future trip_expiry_malformed trip_expiry_past trip_foreign
    trip_invalid_magic_phrase trip_invalid_name trip_missing trip_new_document trip_new_frame trip_phrase
    trip_phrase_missing trip_revoke trip_revoke_missing trip_settings trip_url trip_url_missing)
  @names [
    "failed_live_replacement"
    | for(name <- @cases, locale <- ~w(en de es fr pl ca zh), do: name <> "_" <> locale)
  ]

  for kind <- ~w(live timeline trip track), locale <- ~w(en de es fr pl ca zh) do
    @dom_name "dom/#{kind}_empty_#{locale}"
    @dom_kind String.to_existing_atom(kind)
    @dom_locale locale
    @tag :management_dom
    test "native #{@dom_kind} creation controls in #{@dom_locale} match source DOM" do
      state = File.read!(Path.join(@dir, @dom_name <> ".json")) |> Jason.decode!()
      actor = FrameSeeds.seed_management!(@dom_name)

      if @dom_kind == :track,
        do:
          FrameSeeds.track!(actor.id, 99103, %{
            start_at: ~N[2026-10-03 10:00:00],
            end_at: ~N[2026-10-03 11:00:00],
            distance: 1500,
            dominant_mode: 1
          })

      {:ok, now, _} = DateTime.from_iso8601(state["now"])
      scope = Dawarich.Accounts.Scope.for_user(actor, @dom_locale)

      resource =
        %{type: @dom_kind, owner_id: actor.id}
        |> then(fn r ->
          if @dom_kind in [:trip, :track],
            do: Map.put(r, :id, if(@dom_kind == :trip, do: 99101, else: 99103)),
            else: r
        end)

      {:ok, page} = Sharing.page(scope, resource, %{}, now: now, self_hosted: true)

      html =
        Phoenix.LiveViewTest.render_component(&DawarichWeb.SharingNativeForm.form/1,
          resource: resource,
          page: page,
          locale: @dom_locale,
          values: %{},
          user: actor,
          today: ~D[2026-10-03]
        )

      actual = management_form_dom(html)
      expected = File.read!(Path.join(@dir, @dom_name <> ".html")) |> management_form_dom()
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  for kind <- ~w(live timeline trip track), locale <- ~w(en de es fr pl ca zh) do
    @active_name "dom/#{kind}_active_#{locale}"
    @active_kind String.to_existing_atom(kind)
    @active_locale locale
    @tag :management_active_dom
    test "native #{@active_kind} active controls in #{@active_locale} match source DOM" do
      state = File.read!(Path.join(@dir, @active_name <> ".json")) |> Jason.decode!()
      actor = FrameSeeds.seed_management!(@active_name)

      if @active_kind == :track,
        do:
          FrameSeeds.track!(actor.id, 99103, %{
            start_at: ~N[2026-10-03 10:00:00],
            end_at: ~N[2026-10-03 11:00:00],
            distance: 1500,
            dominant_mode: 1
          })

      {:ok, now, _} = DateTime.from_iso8601(state["now"])
      scope = Dawarich.Accounts.Scope.for_user(actor, @active_locale)

      resource =
        %{type: @active_kind, owner_id: actor.id}
        |> then(fn r ->
          if @active_kind in [:trip, :track],
            do: Map.put(r, :id, if(@active_kind == :trip, do: 99101, else: 99103)),
            else: r
        end)

      {:ok, page} = Sharing.page(scope, resource, %{}, now: now, self_hosted: true)

      html =
        Phoenix.LiveViewTest.render_component(&DawarichWeb.SharingNativeActive.active/1,
          share: page.share,
          locale: @active_locale,
          subtitle: DawarichWeb.SharingNativeActive.subtitle(resource, page, @active_locale),
          base_url: "http://www.example.com"
        )

      actual = management_active_dom(html)
      expected = File.read!(Path.join(@dir, @active_name <> ".html")) |> management_active_dom()
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  @frame_names for(
                 kind <- ~w(live timeline trip track),
                 state <- ~w(empty active),
                 locale <- ~w(en de es fr pl ca zh),
                 do: "dom/#{kind}_#{state}_#{locale}"
               ) ++
                 for(
                   state <-
                     ~w(empty_live empty_timeline empty_make active_live active_timeline active_shared),
                   locale <- ~w(en de es fr pl ca zh),
                   do: "hub_#{state}_#{locale}"
                 )
  for name <- @frame_names do
    @frame_name name
    @tag :management_frame_dom
    test "native manager #{@frame_name} matches source modal and selected panel DOM" do
      state = File.read!(Path.join(@dir, @frame_name <> ".json")) |> Jason.decode!()
      actor = FrameSeeds.seed_management!(@frame_name)
      base = resource(state["path"], actor.id)

      if base.type == :track,
        do:
          FrameSeeds.track!(actor.id, 99103, %{
            start_at: ~N[2026-10-03 10:00:00],
            end_at: ~N[2026-10-03 11:00:00],
            distance: 1500,
            dominant_mode: 1
          })

      locale = actor.settings["locale"]
      {:ok, now, _} = DateTime.from_iso8601(state["now"])
      query = Plug.Conn.Query.decode(URI.parse(state["path"]).query || "")
      scope = Dawarich.Accounts.Scope.for_user(actor, locale)
      {:ok, page} = Sharing.page(scope, base, query, now: now, self_hosted: true)
      tab = if base.type == :hub, do: page.tab, else: "live"

      html =
        Phoenix.LiveViewTest.render_component(&DawarichWeb.SharingLive.Index.render/1,
          current_user: actor,
          current_scope: scope,
          base_resource: base,
          resource: DawarichWeb.SharingResource.selected(base, tab),
          page: page,
          locale: locale,
          tab: tab,
          query_params: query,
          errors: [],
          form_values: %{},
          confirmation: nil,
          base_url: "http://www.example.com",
          today: ~D[2026-10-03]
        )

      assert Dawarich.Test.NativeAdminUI.labels(html) == []
      ids = html |> LazyHTML.from_fragment() |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
      assert length(ids) == MapSet.size(MapSet.new(ids))

      if dir = System.get_env("PARITY_DUMP") do
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, String.replace(@frame_name, "/", "_") <> ".html"), html)
      end

      actual = management_frame_dom(html, tab)
      expected = File.read!(Path.join(@dir, @frame_name <> ".html")) |> management_frame_dom(tab)
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  @report_cases File.read!(Path.join(@dir, "dom/report_pages.json")) |> Jason.decode!()
  for entry <- @report_cases do
    @report entry
    @tag :management_report_dom
    test "native management #{@report["name"]} matches source sharing controls" do
      type = String.to_existing_atom(@report["kind"])

      resource =
        case type do
          :month -> %{type: type, owner_id: 98111, year: 2024, month: 3}
          :digest -> %{type: type, owner_id: 98111, year: 2024}
          :achievement -> %{type: type, owner_id: 98111, key: "country_de"}
        end

      page =
        if type == :achievement,
          do: %{enabled: @report["enabled"], uuid: @report["uuid"]},
          else: %{
            uuid: @report["uuid"],
            settings: %{
              "enabled" => @report["enabled"],
              "expiration" => if(type == :month, do: "1h", else: "24h")
            }
          }

      html =
        Phoenix.LiveViewTest.render_component(&DawarichWeb.SharingNativeReport.form/1,
          resource: resource,
          page: page,
          locale: @report["locale"],
          base_url: "http://www.example.com"
        )

      if dir = System.get_env("PARITY_DUMP") do
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, @report["name"] <> ".html"), html)
      end

      actual = management_report_dom(html, type)

      expected =
        File.read!(Path.join(@dir, "dom/#{@report["name"]}.html")) |> management_report_dom(type)

      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
      assert Dawarich.Test.NativeAdminUI.labels(html) == []
    end
  end

  defp management_report_dom(html, type) do
    document = LazyHTML.from_fragment(html)

    tree =
      if type == :achievement,
        do: LazyHTML.to_tree(document),
        else: document |> LazyHTML.query(".modal-box") |> LazyHTML.to_tree()

    tree |> report_close_wiring() |> form_wiring() |> Dawarich.Test.ParityHTML.normalize()
  end

  defp report_close_wiring(nodes) when is_list(nodes), do: Enum.map(nodes, &report_close_wiring/1)

  defp report_close_wiring({tag, attrs, children}) do
    if tag in ~w(a button) and
         Map.new(attrs)["class"] == "btn btn-sm btn-circle btn-ghost absolute right-2 top-2" do
      {"close-action", Enum.reject(attrs, fn {key, _} -> key in ~w(href type) end),
       report_close_wiring(children)}
    else
      {tag, attrs, report_close_wiring(children)}
    end
  end

  defp report_close_wiring(other), do: other

  defp management_frame_dom(html, tab) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".modal")
    |> LazyHTML.to_tree()
    |> frame_wiring(tab)
    |> form_wiring()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  defp frame_wiring(nodes, tab) when is_list(nodes),
    do: Enum.flat_map(nodes, &frame_wiring(&1, tab))

  defp frame_wiring({"section", attrs, children}, tab) do
    if Map.new(attrs)["data-share-id"],
      do: frame_wiring(children, tab),
      else: [{"section", attrs, frame_wiring(children, tab)}]
  end

  defp frame_wiring({tag, attrs, children}, tab) do
    values = Map.new(attrs)
    panel = tag == "div" and values["style"] == "min-height: 24rem;" and values["data-tab"]

    if panel && values["data-tab"] != tab do
      []
    else
      attrs =
        Enum.map(attrs, fn
          {"class", "hidden pt-2"} -> {"class", "pt-2"}
          {"class", "tab tab-active"} -> {"class", "tab"}
          attr -> attr
        end)

      attrs =
        if values["role"] == "tab",
          do: Enum.reject(attrs, fn {k, _} -> k in ~w(href aria-selected) end),
          else: attrs

      attrs =
        if values["class"] == "modal modal-open",
          do: Enum.reject(attrs, fn {k, _} -> k in ~w(role aria-modal aria-labelledby) end),
          else: attrs

      attrs = Enum.reject(attrs, fn {k, _} -> k == "data-share-id" end)

      {tag, attrs} =
        case {tag, values["data-testid"]} do
          {"button", "hub-make-" <> kind} ->
            {"a",
             Enum.reject(attrs, fn {k, _} -> k == "type" end) ++
               [{"href", "/map/v2?studio=" <> kind}]}

          other ->
            {elem(other, 0), attrs}
        end

      [{tag, attrs, frame_wiring(children, tab)}]
    end
  end

  defp frame_wiring(other, _tab), do: [other]

  defp management_active_dom(html) do
    document = LazyHTML.from_fragment(html)

    selector =
      if Enum.empty?(LazyHTML.query(document, "section[data-share-id]")),
        do: ".modal-box",
        else: "section[data-share-id]"

    [{_, _, children}] = document |> LazyHTML.query(selector) |> LazyHTML.to_tree()

    children
    |> Enum.reject(fn
      {"a", attrs, _} ->
        Map.get(Map.new(attrs), "class") ==
          "btn btn-sm btn-circle btn-ghost absolute right-3 top-3"

      _ ->
        false
    end)
    |> form_wiring()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  defp management_form_dom(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("form:not(.button_to)")
    |> LazyHTML.to_tree()
    |> form_wiring()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  defp form_wiring(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &form_wiring/1)

  defp form_wiring({"input", attrs, _}) do
    attrs =
      Enum.map(attrs, fn {key, value} ->
        {key, if(key in ~w(checked required readonly), do: "", else: value)}
      end)

    values = Map.new(attrs)

    cond do
      values["name"] in ~w(authenticity_token utf8 _method action id _id) ->
        []

      values["name"] == "enabled" and values["value"] == "0" ->
        []

      values["id"] == "share-phrase" ->
        [
          {"input",
           Enum.reject(attrs, fn {k, _} -> k in ~w(value data-private-reveal onclick) end) ++
             [{"value", ""}], []}
        ]

      values["name"] == "shared_link[magic_phrase]" ->
        [
          {"input",
           attrs
           |> Enum.reject(fn {k, _} -> k in ~w(value id autocomplete data-url) end)
           |> Kernel.++([{"value", ""}, {"id", "shared_link_magic_phrase"}]), []}
        ]

      values["type"] == "hidden" ->
        [{"input", Enum.reject(attrs, fn {k, _} -> k == "id" end), []}]

      true ->
        [{"input", Enum.reject(attrs, fn {k, _} -> k == "onclick" end), []}]
    end
  end

  defp form_wiring({"span", attrs, _} = node) do
    if Map.new(attrs)["data-status"] != nil, do: [], else: [node]
  end

  defp form_wiring({tag, attrs, children}) do
    attrs = Enum.reject(attrs, fn {key, _} -> key in ~w(data-reveal onclick) end)

    attrs =
      Enum.map(attrs, fn {key, value} ->
        {key, if(key in ~w(hidden selected), do: "", else: value)}
      end)

    attrs =
      if tag == "button" and
           Map.new(attrs)["class"] == "btn btn-sm btn-circle btn-ghost absolute right-2 top-2",
         do: List.keystore(attrs, "type", 0, {"type", "button"}),
         else: attrs

    attrs =
      if Map.new(attrs)["phx-hook"] == "SharingReveal",
        do:
          Enum.reject(attrs, fn {k, _} ->
            k in ~w(data-url data-copied-label data-failed-label)
          end),
        else: attrs

    attrs =
      if tag == "button" and Map.new(attrs)["phx-hook"] == "Clipboard",
        do:
          Enum.reject(attrs, fn {key, _} ->
            key in ~w(data-clipboard-text data-clipboard-url data-copied-label data-failed-label data-status-id)
          end),
        else: attrs

    attrs =
      if tag == "form",
        do: Enum.reject(attrs, fn {key, _} -> key in ~w(action method accept-charset id) end),
        else: attrs

    attrs =
      if tag == "label", do: Enum.reject(attrs, fn {key, _} -> key == "for" end), else: attrs

    [{tag, attrs, form_wiring(children)}]
  end

  defp form_wiring(other), do: [other]

  @domain_names for type <- ~w(track timeline),
                    action <-
                      ~w(new head empty_new create invalid url phrase revoke recreate delete),
                    do: "a12f3b/#{type}_#{action}_en"
  @domain_cases ["a12f3b/track_foreign_en" | @domain_names]

  setup do
    old = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, old) end)
    :ok
  end

  test "management corpus is complete" do
    actual =
      @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".json"))

    assert Enum.sort(actual) == Enum.sort(@names)
    assert length(@names) == 505
  end

  for name <- @names ++ @domain_cases do
    @name name
    @tag management_case: name
    test "native management #{@name} preserves scoped inputs persisted rows and wire effects" do
      state = Path.join(@dir, @name <> ".json") |> File.read!() |> Jason.decode!()
      user = FrameSeeds.seed_management!(@name)

      if @name in @domain_cases do
        for {id, owner} <- [{99103, 98101}, {99104, 98102}] do
          FrameSeeds.track!(owner, id, %{
            start_at: ~N[2026-10-03 08:00:00],
            end_at: ~N[2026-10-03 09:00:00],
            distance: 1500,
            dominant_mode: 1
          })
        end
      end

      now = state["now"] |> DateTime.from_iso8601() |> elem(1)

      locale =
        DawarichWeb.Locale.resolve(
          Plug.Conn.Query.decode(URI.parse(state["path"]).query || "")["locale"],
          user,
          %{}
        )

      scope = Dawarich.Accounts.Scope.for_user(user, locale)
      resource = resource(state["path"], user && user.id)
      params = state["params"] || %{}
      query = Plug.Conn.Query.decode(URI.parse(state["path"]).query || "")

      if state["verb"] in ~w(GET HEAD) do
        result = Sharing.page(scope, resource, query, now: now, self_hosted: true)

        cond do
          user == nil ->
            assert {:error, :stale_session} = result

          state["status"] == 404 ->
            assert {:error, :not_found} = result

          state["status"] == 200 ->
            assert {:ok, page} = result
            refute inspect(page) =~ "magic_phrase"
            assert_read(page, state, user, resource, now)

          true ->
            assert {:error, _} = result
        end

        assert rows() == state["before"]
      else
        action = action(state)

        if Map.has_key?(state["headers"], "X-HTTP-Method-Override") do
          assert Phoenix.Router.route_info(
                   DawarichWeb.Router,
                   state["verb"],
                   URI.parse(state["path"]).path,
                   "www.example.com"
                 ) == :error

          assert rows() == state["before"]
          assert events() == []
        else
          result = Sharing.change(scope, resource, action, params, now: now, self_hosted: true)

          if state["after"] == state["before"] do
            assert {:error, _} = result
          else
            assert {:ok, value} = result
            refute inspect(value) =~ "magic_phrase"
          end

          assert normalize_rows(rows(), state) == normalize_rows(state["after"], state)
          assert events() == state["events"]
          assert_error_text(result, @name, locale)
        end
      end
    end
  end

  defp resource(path, owner) do
    type =
      cond do
        String.starts_with?(path, "/share_links/hub") -> :hub
        String.starts_with?(path, "/share_links/live") -> :live
        String.starts_with?(path, "/share_links/timeline") -> :timeline
        String.starts_with?(path, "/share_links/shares/") -> :shared
        String.starts_with?(path, "/tracks/") -> :track
        true -> :trip
      end

    resource = %{type: type, owner_id: owner}

    if type in [:trip, :track, :shared] do
      raw =
        URI.parse(path).path
        |> String.split("/", trim: true)
        |> Enum.at(if(type == :shared, do: 2, else: 1))

      Map.put(resource, :id, if(type == :shared, do: raw, else: String.to_integer(raw)))
    else
      resource
    end
  end

  defp action(state) do
    suffix = URI.parse(state["path"]).path |> String.split("/") |> List.last()

    cond do
      state["verb"] == "DELETE" -> :destroy
      suffix == "revoke" -> :revoke
      suffix == "regenerate" -> :regenerate
      suffix == "regenerate_phrase" -> :regenerate_phrase
      true -> :create
    end
  end

  defp assert_read(page, state, user, resource, now) do
    links = if resource.type == :hub, do: page.shares, else: List.wrap(page[:share])

    expected =
      Enum.filter(state["before"], fn row ->
        row["user_id"] == user.id and row["revoked_at"] == nil and
          (row["expires_at"] == nil or
             String.replace(row["expires_at"], " ", "T") >
               NaiveDateTime.to_iso8601(DateTime.to_naive(now)))
      end)

    if resource.type == :hub,
      do: assert(Enum.sort(Enum.map(links, & &1.id)) == Enum.sort(Enum.map(expected, & &1["id"])))

    for link <- links do
      source = Enum.find(state["before"], &(&1["id"] == link.id))
      assert source

      assert Map.take(link, [:name, :resource_type, :resource_id, :settings, :view_count])
             |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end) ==
               Map.take(source, ~w(name resource_type resource_id settings view_count))
    end

    if resource.type == :hub do
      assert page.tab in ~w(live timeline make shared unknown)

      assert Enum.map(page.shares, & &1.created_at) ==
               Enum.sort(Enum.map(page.shares, & &1.created_at), {:desc, NaiveDateTime})
    end
  end

  defp assert_error_text({:error, %{errors: errors}}, name, _locale) do
    field =
      cond do
        String.contains?(name, "expiry_past") or String.contains?(name, "invalid_frame") ->
          :expires_at

        String.contains?(name, "invalid_magic_phrase") or String.contains?(name, "invalid_hub") or
          String.contains?(name, "/track_invalid") or String.contains?(name, "/timeline_invalid") or
            name == "failed_live_replacement" ->
          :magic_phrase

        true ->
          :name
      end

    assert [{^field, message}] = errors
    assert is_binary(message) and String.trim(message) != ""
  end

  defp assert_error_text(_, _, _), do: :ok

  defp rows,
    do:
      Repo.query!("SELECT row_to_json(t) FROM shared_links t ORDER BY id").rows |> List.flatten()

  defp events do
    for [stream, payload] <-
          Repo.query!("SELECT channel,payload FROM phoenix.cable_events ORDER BY seq").rows do
      %{"stream" => stream, "message" => Jason.decode!(payload)}
    end
  end

  defp normalize_rows(rows, state) do
    before = Enum.map(state["before"], & &1["id"])

    Enum.map(rows, fn row ->
      row = if row["id"] in before, do: row, else: Map.put(row, "id", "NEW-ID")

      if String.ends_with?(state["path"], "regenerate_phrase") and
           row["magic_phrase"] not in [nil, "old-fixture-phrase"],
         do: Map.put(row, "magic_phrase", "PHRASE"),
         else: row
    end)
    |> Enum.sort_by(& &1["id"])
  end
end
