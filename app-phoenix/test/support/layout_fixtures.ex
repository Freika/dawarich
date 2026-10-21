defmodule Dawarich.Test.LayoutFixtures do
  @moduledoc false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  @dir "test/fixtures/layout"

  def names do
    @dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".json"))
    |> Enum.reject(&(&1 == "flash_messages"))
  end

  def load(name) do
    {
      File.read!(Path.join(@dir, name <> ".html")),
      @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
    }
  end

  def load_head(name), do: File.read!(Path.join(@dir, name <> ".head.html"))

  def flash_messages,
    do: @dir |> Path.join("flash_messages.json") |> File.read!() |> Jason.decode!()

  alias Dawarich.{Jobs, Repo}

  @now ~U[2026-09-26 12:00:00Z]

  def render(state) do
    user = insert(state)
    locale = DawarichWeb.Locale.resolve(state["locale"], user, %{})

    if url = state["manager_url"],
      do: System.put_env("MANAGER_URL", url),
      else: System.delete_env("MANAGER_URL")

    assigns = %{
      current_user: user,
      native: true,
      locale: locale,
      suggested_locale:
        DawarichWeb.Locale.suggest(state["accept_language"], nil, user, %{}, locale),
      self_hosted: state["self_hosted"],
      flash: %{},
      flash_messages: [],
      now: @now,
      request_path: URI.parse(state["path"]).path,
      query_params: %{},
      rails_csrf_token: nil,
      morph_page_refreshes: URI.parse(state["path"]).path == "/notifications",
      base_url: "http://www.example.com",
      page_title:
        if(state["layout"] == "map",
          do: DawarichWeb.Translate.t(locale, "map.maplibre.index.map", %{}),
          else: page_title(locale, user)
        ),
      viewport:
        if(state["layout"] == "map",
          do: "width=device-width,initial-scale=1,viewport-fit=cover",
          else: "width=device-width,initial-scale=1"
        ),
      body_class:
        if(state["layout"] == "map",
          do: "h-screen !h-[100dvh] overflow-hidden relative",
          else: "min-h-screen flex flex-col"
        ),
      page: %{demo_data: false},
      navbar: Dawarich.Navbar.load(user, now: @now, self_hosted: state["self_hosted"])
    }

    layout =
      if state["layout"] == "map",
        do: &DawarichWeb.Layouts.map/1,
        else: &DawarichWeb.Layouts.app/1

    inner = render_component(layout, Map.put(assigns, :inner_content, ""))

    render_component(
      &DawarichWeb.Layouts.root/1,
      Map.put(assigns, :inner_content, Phoenix.HTML.raw(inner))
    )
  end

  def region(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> chrome_wiring()
    |> flash_wiring()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  def public_region(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> public_classes()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  defp public_classes(nodes) when is_list(nodes), do: Enum.map(nodes, &public_classes/1)

  defp public_classes({tag, attrs, children}) do
    replacements = %{
      "container mx-auto px-4 py-2 flex min-w-0 flex-wrap items-center justify-between gap-2 min-h-16" =>
        "container mx-auto px-4 flex items-center justify-between h-16",
      "max-w-xl min-w-0 [overflow-wrap:anywhere]" => "max-w-xl",
      "inline-flex min-w-0 flex-wrap items-center gap-2 rounded-lg bg-gradient-to-b from-[#3A66E8] to-[#2A56D8] px-4 py-2 text-sm font-bold text-white shadow-[0_6px_16px_rgba(45,91,227,0.30)] transition hover:brightness-105" =>
        "inline-flex items-center gap-2 rounded-lg bg-gradient-to-b from-[#3A66E8] to-[#2A56D8] px-4 py-2 text-sm font-bold text-white shadow-[0_6px_16px_rgba(45,91,227,0.30)] transition hover:brightness-105"
    }

    attrs =
      Enum.map(attrs, fn
        {"class", value} -> {"class", Map.get(replacements, value, value)}
        pair -> pair
      end)

    {tag, attrs, public_classes(children)}
  end

  defp public_classes(other), do: other

  defp chrome_wiring(nodes) when is_list(nodes), do: Enum.map(nodes, &chrome_wiring/1)

  defp chrome_wiring({"form", attrs, children} = node) do
    if Map.new(attrs)["action"] == "/users/sign_out" do
      values = for {"input", attrs, _} <- children, do: Map.new(attrs)

      unless Map.new(attrs)["method"] == "post" and
               Enum.any?(values, &(&1["name"] == "_method" and &1["value"] == "delete")) and
               Enum.any?(values, &(&1["name"] == "authenticity_token" and &1["type"] == "hidden")),
             do: raise("invalid native sign-out form")

      [{"button", _, label}] = Enum.filter(children, &match?({"button", _, _}, &1))
      {"a", [{"href", "/users/sign_out"}, {"rel", "nofollow"}, {"data-method", "delete"}], label}
    else
      chrome_node(node)
    end
  end

  defp chrome_wiring({_, _, _} = node), do: chrome_node(node)
  defp chrome_wiring(node), do: node

  defp chrome_node({tag, attrs, children}) do
    {tag, attrs} =
      if tag == "button" and Map.new(attrs)["class"] == "relative whitespace-nowrap" do
        values = Map.new(attrs)

        unless values["type"] == "button" and
                 ((values["phx-click"] || "") =~ "getting_started" or
                    values["data-auth-open-dialog"] == "getting_started"),
               do: raise("invalid native onboarding action")

        {"a", Enum.reject(attrs, fn {key, _} -> key in ~w(type data-auth-open-dialog) end)}
      else
        {tag, attrs}
      end

    attrs =
      Enum.reject(attrs, fn
        {"onclick", "getting_started.showModal()"} -> true
        {"id", id} -> id in ~w(family-navbar-indicator family-navbar-indicator-mobile)
        _ -> false
      end)

    {tag, attrs, chrome_wiring(children)}
  end

  defp flash_wiring(nodes, inside \\ false)

  defp flash_wiring(nodes, inside) when is_list(nodes),
    do: Enum.map(nodes, &flash_wiring(&1, inside))

  defp flash_wiring({tag, attrs, children}, inside) do
    values = Map.new(attrs)
    inside = inside or values["role"] == "alert" or values["id"] == "flash-messages"

    replacements = %{
      "fixed top-5 right-5 max-w-[calc(100vw-2.5rem)] flex flex-col gap-2 z-50 pointer-events-none" =>
        "fixed top-5 right-5 flex flex-col gap-2 z-50",
      "flex min-w-0 max-w-full items-start gap-2" => "flex items-center gap-2",
      "size-6 shrink-0" => "size-6",
      "btn btn-sm btn-circle btn-ghost pointer-events-auto shrink-0" =>
        "btn btn-sm btn-circle btn-ghost"
    }

    normalized =
      Enum.flat_map(attrs, fn
        {"tabindex", "-1"} ->
          []

        {name, _}
        when name in ~w(data-auth-error-summary data-auth-flash data-auth-flash-timeout data-auth-flash-dismiss) ->
          []

        {"class", "min-w-0 [overflow-wrap:anywhere]"} ->
          []

        {"class", "native-flash alert " <> rest} ->
          [
            {"class",
             "alert " <>
               String.replace_suffix(rest, " min-w-0 max-w-full pointer-events-none", "")}
          ]

        {"class", value} ->
          [{"class", Map.get(replacements, value, value)}]

        other ->
          [other]
      end)

    {tag, if(inside, do: normalized, else: attrs), flash_wiring(children, inside)}
  end

  defp flash_wiring(other, _inside), do: other

  defp page_title(_locale, nil), do: nil

  defp page_title(locale, _user) do
    {:ok, title} = Dawarich.I18n.t(locale, "notifications.index.notifications")
    title
  end

  defp insert(%{"user" => nil}), do: nil

  defp insert(%{"user" => user} = state) do
    insert_user(user)
    insert_family(state["family"], user["id"])

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "notifications",
      for n <- state["notifications"] do
        at = naive(n["created_at"])

        %{
          id: n["id"],
          user_id: user["id"],
          title: n["title"],
          content: "x",
          kind: kind(n["kind"]),
          read_at: if(n["read"], do: at),
          created_at: at,
          updated_at: at
        }
      end
    )

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "imports",
      for i <- state["imports"] || [] do
        %{
          id: i["id"],
          user_id: user["id"],
          name: i["name"],
          demo: i["demo"],
          created_at: ~N[2026-09-01 00:00:00],
          updated_at: ~N[2026-09-01 00:00:00]
        }
      end
    )

    if state["supporter"] do
      hash =
        Base.encode16(:crypto.hash(:sha256, user["settings"]["supporter_email"]), case: :lower)

      Jobs.repo().query!(
        "INSERT INTO phoenix.supporter_checks (cache_key, result, checked_at) VALUES ($1, $2, $3)",
        ["dawarich/supporter:" <> hash, %{"supporter" => true}, @now]
      )
    end

    Dawarich.Accounts.get(user["id"])
  end

  defp insert_user(user) do
    stamp = ~N[2026-09-01 00:00:00]

    struct(Dawarich.Accounts.User,
      id: user["id"],
      email: user["email"],
      theme: user["theme"],
      settings: user["settings"],
      admin: user["admin"]
    )
    |> then(fn _ ->
      Dawarich.Test.SeedIds.insert_all!(Repo, "users", [
        %{
          id: user["id"],
          email: user["email"],
          encrypted_password: "",
          theme: user["theme"] || "dark",
          settings: user["settings"] || %{},
          admin: user["admin"] || false,
          status: user["status"] || 1,
          plan: Map.get(user, "plan", 1),
          active_until: naive(user["active_until"]),
          subscription_source: user["subscription_source"] || 0,
          changelog_consent: user["changelog_consent"],
          api_key: user["api_key"] || "",
          created_at: stamp,
          updated_at: stamp
        }
      ])
    end)
  end

  defp insert_family(nil, _user_id), do: :ok

  defp insert_family(family, user_id) do
    stamp = ~N[2026-09-01 00:00:00]
    creator = family["creator"]
    if creator["id"] != user_id, do: insert_user(creator)

    Dawarich.Test.SeedIds.insert_all!(Repo, "families", [
      %{
        id: family["id"],
        name: "F",
        creator_id: creator["id"],
        access_until: naive(family["access_until"]),
        created_at: stamp,
        updated_at: stamp
      }
    ])

    members = [
      {user_id, family["role"]} | if(creator["id"] != user_id, do: [{creator["id"], 0}], else: [])
    ]

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "family_memberships",
      for(
        {id, role} <- members,
        do: %{
          family_id: family["id"],
          user_id: id,
          role: role,
          created_at: stamp,
          updated_at: stamp
        }
      )
    )
  end

  defp naive(nil), do: nil
  defp naive(iso), do: NaiveDateTime.from_iso8601!(iso)

  defp kind("info"), do: 0
  defp kind("warning"), do: 1
  defp kind("error"), do: 2
  defp kind(kind) when kind in 0..2, do: kind
end
