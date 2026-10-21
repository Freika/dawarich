defmodule Dawarich.Users do
  @moduledoc false

  import Ecto.Query

  @counted_statuses [1, 2]

  def correct_points_counts(repo, after_id, limit) do
    users =
      from(u in "users",
        where: u.id > ^after_id and u.status in @counted_statuses and is_nil(u.deleted_at),
        order_by: u.id,
        limit: ^limit,
        select: {u.id, u.points_count}
      )
      |> repo.all()

    Enum.each(users, fn {id, stored} ->
      actual = repo.one(from(p in "points", where: p.user_id == ^id, select: count()))

      if actual != stored do
        repo.update_all(from(u in "users", where: u.id == ^id), set: [points_count: actual])
      end
    end)

    if length(users) == limit, do: {:next, users |> List.last() |> elem(0)}, else: :done
  end
end
