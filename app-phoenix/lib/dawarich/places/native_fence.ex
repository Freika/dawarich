defmodule Dawarich.Places.NativeFence do
  @moduledoc false
  alias Dawarich.Places.Access

  def check(repo, id, %{native_scope: original}) do
    with {:ok, scope} <- Access.admit(original),
         :ok <- Access.settings(scope) do
      if id && foreign?(repo, id, scope.user.id),
        do: {:error, :foreign_dependents},
        else: :ok
    end
  end

  def check(_, _, _), do: :ok

  defp foreign?(repo, id, owner) do
    [[foreign]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM visits WHERE place_id=$1 AND user_id IS DISTINCT FROM $2) OR EXISTS(SELECT 1 FROM place_visits pv JOIN visits v ON v.id=pv.visit_id WHERE pv.place_id=$1 AND v.user_id IS DISTINCT FROM $2) OR EXISTS(SELECT 1 FROM taggings g JOIN tags t ON t.id=g.tag_id WHERE g.taggable_type='Place' AND g.taggable_id=$1 AND t.user_id IS DISTINCT FROM $2) OR EXISTS(SELECT 1 FROM notes WHERE attachable_type='Place' AND attachable_id=$1 AND user_id IS DISTINCT FROM $2)",
        [id, owner],
        log: false
      ).rows

    foreign
  end
end
