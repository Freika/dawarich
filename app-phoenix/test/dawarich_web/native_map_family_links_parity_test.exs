defmodule DawarichWeb.NativeMapFamilyLinksParityTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{ParityHTML, RailsUser}
  @endpoint DawarichWeb.Endpoint
  @fixture "test/fixtures/map_ui/rails-1.16.0-family-links.html"
  @selectors [
    ~s([data-tab="family"]),
    ~s([data-tab="links"]),
    ~s([data-tab-content="family"]),
    ~s([data-tab-content="links"])
  ]

  setup do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-map-family-links-fixture-signing-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)
  end

  for {state, role, sharing, self_hosted} <- [
        {"owner_without_locations", :owner, false, true},
        {"owner_with_locations", :owner, true, true},
        {"member_without_locations", :member, false, true},
        {"member_with_locations", :member, true, true},
        {"non_member_self_hosted", nil, false, true},
        {"non_member_cloud", nil, false, false}
      ] do
    test "#{state} Family and Links tabs and launchers match Rails 1.16.0" do
      id = actor(unquote(role), unquote(sharing))

      if unquote(role) do
        scope = %Dawarich.Accounts.Scope{user: Dawarich.Accounts.get(id), locale: "en"}

        assert {:ok, %{locations: locations}} =
                 Dawarich.Families.locations(scope, self_hosted: true)

        assert Enum.empty?(locations) == not unquote(sharing)
      end

      html = page(id, unquote(self_hosted))
      expected = rails(unquote(state))

      for selector <- @selectors do
        actual = fragment(html, selector)
        expected = fragment(expected, selector)
        dump(unquote(state) <> selector, actual, expected)
        assert actual == expected, ParityHTML.first_difference(actual, expected)
      end
    end
  end

  defp actor(role, sharing) do
    owner = user()

    if role do
      member = user()

      [[family]] =
        Repo.query!(
          "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Fixture family',$1,now(),now()) RETURNING id",
          [owner]
        ).rows

      for {id, role} <- [{owner, 1}, {member, 0}] do
        Repo.query!(
          "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,$3,now(),now())",
          [family, id, role]
        )
      end

      if sharing do
        for member <- [owner, member] do
          Repo.query!("UPDATE users SET settings=settings || $2 WHERE id=$1", [
            member,
            %{"family" => %{"location_sharing" => %{"enabled" => true}}}
          ])

          Repo.query!(
            "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1790676000,ST_GeogFromText('POINT(13.4 52.5)'),now(),now())",
            [member]
          )
        end
      end

      if role == :owner, do: owner, else: member
    else
      owner
    end
  end

  defp user do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "family-links-#{id}@example.invalid",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    id
  end

  defp page(id, self_hosted) do
    conn =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> Plug.Conn.assign(:locale, "en")
      |> Plug.Conn.assign(:self_hosted, self_hosted)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{
        request_path: "/map/v2",
        path_info: ["map", "v2"],
        query_string: "locale=en"
      })
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeM6IntegrationRouter.call([])

    {:ok, view, _html} = live(conn)
    render(view)
  end

  defp fragment(html, selector) do
    html
    |> ParityHTML.fragment(selector)
    |> wiring()
  end

  defp wiring(nodes) when is_list(nodes), do: Enum.map(nodes, &wiring/1)

  defp wiring({tag, attrs, children}) do
    attrs =
      cond do
        tag == "input" and {"type", "checkbox"} in attrs ->
          Enum.reject(attrs, fn {key, _} -> key in ~w(name value form checked) end)

        tag == "a" and {"rel", "noopener noreferrer"} in attrs ->
          List.keydelete(attrs, "rel", 0)

        true ->
          attrs
      end

    {tag, attrs, wiring(children)}
  end

  defp wiring(text), do: text

  defp rails(name) do
    @fixture
    |> File.read!()
    |> String.split("<!-- section:")
    |> Enum.find_value(fn part ->
      case String.split(part, " -->\n", parts: 2) do
        [^name, markup] -> "<html><body>" <> markup <> "</body></html>"
        _ -> nil
      end
    end)
  end

  defp dump(name, actual, expected) do
    if dir = System.get_env("PARITY_DUMP") do
      File.mkdir_p!(dir)

      for {suffix, tree} <- [{"phoenix", actual}, {"rails", expected}] do
        File.write!(
          Path.join(dir, name <> "." <> suffix),
          inspect(tree, pretty: true, limit: :infinity)
        )
      end
    end
  end
end
