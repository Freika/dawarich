defmodule DawarichWeb.PublicReportDocument do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Assets, Layouts, NativePublicMonth, PublicDigest}

  def document(assigns) do
    content = content(assigns)

    root =
      Map.merge(assigns.chrome, %{
        __changed__: nil,
        page_title: nil,
        inner_content: content
      })

    app = Layouts.auth_app(root)
    Layouts.auth_root(Map.put(root, :inner_content, app))
  end

  defp content(assigns) do
    ~H"""
    <%= if @page.kind == :month do %>
      <NativePublicMonth.content {assigns} />
    <% else %>
      <PublicDigest.document
        digest={@page.digest}
        full={@page.full}
        totals={@page.totals}
        unit={@page.unit}
        locale={@locale}
        table={Dawarich.CountryNames.table()}
        native
      />
      <nav
        :if={@page.page > 1 or @page.more}
        class="flex flex-wrap justify-center gap-3"
        aria-label={t(@locale, "achievements.ui.collection_pages", %{})}
      >
        <a :if={@page.page > 1} rel="prev" href={"?page=#{@page.page - 1}"}>{t(
          @locale,
          "achievements.ui.prev_page",
          %{}
        )}</a>
        <a :if={@page.more} rel="next" href={"?page=#{@page.page + 1}"}>{t(
          @locale,
          "achievements.ui.next_page",
          %{}
        )}</a>
      </nav>
    <% end %>
    <script type="module" src={Assets.native_path("public_charts.js")}>
    </script>
    """
  end
end
