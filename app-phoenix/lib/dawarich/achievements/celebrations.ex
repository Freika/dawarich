defmodule Dawarich.Achievements.Celebrations do
  @moduledoc false

  def record_seen!(_repo, _user_id, [], _stamp), do: :ok

  def record_seen!(repo, user_id, keys, stamp) do
    {:ok, :ok} =
      repo.transaction(fn ->
        case repo.query!(
               "SELECT id,state FROM achievement_progresses WHERE user_id=$1 AND achievement_key='exploration' FOR UPDATE",
               [user_id],
               log: false
             ).rows do
          [[id, state]] ->
            stamp = if is_function(stamp, 0), do: stamp.(), else: stamp
            celebrated = Map.get(state, "celebrated", %{})
            next = Enum.reduce(keys, celebrated, &Map.put(&2, &1, stamp))

            repo.query!(
              "UPDATE achievement_progresses SET state=$2,updated_at=now() WHERE id=$1",
              [id, Map.put(state, "celebrated", next)],
              log: false
            )

          [] ->
            :ok
        end

        :ok
      end)

    :ok
  end
end
