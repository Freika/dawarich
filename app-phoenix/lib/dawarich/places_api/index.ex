defmodule Dawarich.PlacesApi.Index do
  @moduledoc false

  alias Dawarich.PlacesApi.Payload
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo

  @confirmed "p.id IN (SELECT visits.place_id FROM visits WHERE visits.user_id = $1 " <>
               "AND visits.deleted_at IS NULL AND visits.status != 2 AND visits.status = 1 " <>
               "AND visits.place_id IS NOT NULL)"
  @tagged "p.id IN (SELECT taggings.taggable_id FROM taggings WHERE taggings.taggable_type = 'Place')"
  @number ~r/\A[1-9]\d{0,8}\z/

  def read(owner, params) do
    cond do
      Ruby.present?(params["tag_ids"]) ->
        {:replay, "places tag filter"}

      not (is_nil(params["per_page"]) or is_binary(params["per_page"])) ->
        {:replay, "places per_page shape"}

      not Ruby.present?(params["page"]) ->
        where = where(params["filter"])
        total = count(owner, where)
        {:ok, 200, Payload.places(owner, where, []), headers(1, 1, total)}

      page?(params["page"], params["per_page"]) ->
        page(owner, where(params["filter"]), params)

      true ->
        {:replay, "places page parameters"}
    end
  end

  defp page(owner, where, params) do
    number = String.to_integer(params["page"])
    per = min(String.to_integer(params["per_page"] || "100"), 500)
    total = count(owner, where)
    rows = Payload.places(owner, where, [], " LIMIT #{per} OFFSET #{(number - 1) * per}")
    {:ok, 200, rows, headers(number, div(total + per - 1, per), total)}
  end

  defp page?(page, per),
    do: is_binary(page) and page =~ @number and (is_nil(per) or per =~ @number)

  defp where("all"), do: "TRUE"
  defp where("manual"), do: "p.source = 0"
  defp where("confirmed"), do: @confirmed
  defp where("tagged"), do: @tagged
  defp where(_filter), do: "(p.source = 0 OR p.source = 2 OR #{@confirmed} OR #{@tagged})"

  defp count(owner, where) do
    [[total]] =
      Repo.query!("SELECT count(*) FROM places p WHERE p.user_id = $1 AND " <> where, [owner]).rows

    total
  end

  defp headers(page, pages, total),
    do: [
      {"x-current-page", Integer.to_string(page)},
      {"x-total-pages", Integer.to_string(pages)},
      {"x-total-count", Integer.to_string(total)}
    ]
end
