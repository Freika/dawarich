defmodule DawarichWeb.InsightsFrameTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias DawarichWeb.InsightsFrameLayout

  test "retained map frame layout has only html/head/body and conditional Rails CSRF metas" do
    html =
      render_component(&InsightsFrameLayout.render/1, %{
        inner_content:
          Phoenix.HTML.raw("<turbo-frame id=\"insights_details\">synthetic</turbo-frame>"),
        rails_csrf_token: nil
      })

    assert html =~ "<html>"
    refute html =~ "<!DOCTYPE"
    refute html =~ "<title"
    refute html =~ "<nav"
    refute html =~ "<footer"
    refute html =~ "<script"
    refute html =~ "<meta"

    csrf =
      render_component(&InsightsFrameLayout.render/1, %{
        inner_content: "synthetic",
        rails_csrf_token: "synthetic-masked-token"
      })

    assert csrf =~ "csrf-param"
    assert csrf =~ "csrf-token"
    refute csrf =~ "phoenix-csrf-token"
  end
end
