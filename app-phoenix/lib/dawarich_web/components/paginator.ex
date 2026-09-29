defmodule DawarichWeb.Paginator do
  @moduledoc false
  use DawarichWeb, :html

  @window 4
  @form_keys ~w(authenticity_token commit utf8 _method script_name original_script_name)

  attr :locale, :string, required: true
  attr :path, :string, required: true
  attr :query, :map, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true

  def paginator(assigns) do
    assigns = assign(assigns, :tags, tags(assigns.page, assigns.total_pages))

    ~H"""
    <div
      :if={@tags != []}
      class="join"
      role="navigation"
      aria-label={t(@locale, "kaminari.paginator.pager", %{})}
    >
      <%= for tag <- @tags do %>
        <%= case tag do %>
          <% :prev -> %>
            <.link patch={url(@path, @query, @page - 1)} rel="prev" class="join-item btn">{t(
              @locale,
              "kaminari.prev_page.laquo",
              %{}
            )}</.link>
          <% :next -> %>
            <.link patch={url(@path, @query, @page + 1)} rel="next" class="join-item btn">{t(
              @locale,
              "kaminari.next_page.raquo",
              %{}
            )}</.link>
          <% :gap -> %>
            <button class="join-item btn btn-disabled">...</button>
          <% {:page, number} -> %>
            <%= if number == @page do %>
              <button class="join-item btn btn-active">{number}</button>
            <% else %>
              <.link patch={url(@path, @query, number)} rel={rel(number, @page)} class="join-item btn">{number}</.link>
            <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  def tags(_page, total) when total <= 1, do: []

  def tags(page, total) do
    {pages, _last} =
      Enum.reduce(relevant(page, total), {[], if(page == 1, do: nil, else: :prev)}, fn number,
                                                                                       {acc, last} ->
        cond do
          display?(number, page, total) -> {[{:page, number} | acc], :page}
          last != :gap -> {[:gap | acc], :gap}
          true -> {acc, last}
        end
      end)

    prev = if page == 1, do: [], else: [:prev]
    next = if page >= total, do: [], else: [:next]
    prev ++ Enum.reverse(pages) ++ next
  end

  defp relevant(page, total),
    do:
      Enum.filter(
        Enum.uniq(
          Enum.sort([1, total | Enum.to_list((page - @window - 1)..(page + @window + 1))])
        ),
        &(&1 >= 1 and &1 <= total)
      )

  defp display?(number, page, total),
    do:
      abs(page - number) <= @window or (number == page - @window - 1 and number == 1) or
        (number == page + @window + 1 and number == total)

  defp rel(number, page) when number == page + 1, do: "next"
  defp rel(number, page) when number == page - 1, do: "prev"
  defp rel(_number, _page), do: nil

  defp url(path, query, number) do
    query = query |> Map.drop(@form_keys) |> Map.delete("page")
    query = if number > 1, do: Map.put(query, "page", Integer.to_string(number)), else: query

    case query |> Enum.map(&URI.encode_query([&1])) |> Enum.sort() |> Enum.join("&") do
      "" -> path
      encoded -> path <> "?" <> encoded
    end
  end
end
