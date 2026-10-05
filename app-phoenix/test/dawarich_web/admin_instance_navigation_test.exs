defmodule DawarichWeb.AdminInstanceNavigationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  test "section links navigate the document with their section query and history" do
    data = %{
      fields: %{"reverse_geocoding_rps" => %{unreadable: false, pinned: false}},
      geocoding: %{enabled: false}
    }

    html =
      render_component(&DawarichWeb.AdminInstance.section_link/1,
        locale: "en",
        item: "rate_limit",
        section: "photon",
        data: data
      )

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(~s(a[href="/admin/settings?section=rate_limit"][data-turbo="false"]))
           |> Enum.count() == 1
  end
end
