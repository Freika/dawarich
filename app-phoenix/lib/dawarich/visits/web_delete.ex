defmodule Dawarich.Visits.WebDelete do
  @moduledoc false
  alias Dawarich.Visits.{WebEffects, WebScope}

  def run(repo, user, id, _params, context) do
    with {:ok, id} <- WebEffects.single_id(id),
         {:ok, zone} <- WebEffects.zone(repo, user, context) do
      WebEffects.transact(repo, fn ->
        with {:ok, [old]} <- WebScope.load(repo, user, [id], context.now, context.self_hosted),
             :ok <- WebEffects.validate(old) do
          new =
            WebEffects.persist(
              repo,
              old,
              Map.put(old, "deleted_at", DateTime.to_naive(context.now)),
              context.now
            )

          WebEffects.after_change(repo, user, old, new, context)
          new = WebEffects.adopt(repo, old, new, context.now, false)
          {:ok, %{visit: new, old: old, zone: zone}}
        end
      end)
    end
  end
end
