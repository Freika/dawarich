defmodule DawarichWeb.LiveTitleTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  test "shared roots preserve the localized full title after a LiveView connects" do
    for root <- [&DawarichWeb.Layouts.root/1, &DawarichWeb.Layouts.map_root/1],
        {locale, title} <- [
          {"en", "2024 Year in Review"},
          {"de", "Statistiken"},
          {"es", "Estadísticas"},
          {"en", nil}
        ] do
      html =
        render_component(root,
          locale: locale,
          page_title: title,
          current_user: nil,
          self_hosted: true,
          rails_csrf_token: nil,
          inner_content: ""
        )

      element = html |> LazyHTML.from_document() |> LazyHTML.query("title")
      app_name = DawarichWeb.Layouts.page_title(locale, nil)
      assert LazyHTML.attribute(element, "data-default") == [app_name]

      assert LazyHTML.attribute(element, "data-suffix") ==
               if(title, do: [DawarichWeb.Layouts.page_title(locale, "")], else: [])

      assert LazyHTML.text(element) == DawarichWeb.Layouts.page_title(locale, title)
    end
  end
end
