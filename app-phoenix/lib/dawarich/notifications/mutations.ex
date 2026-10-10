defmodule Dawarich.Notifications.Mutations do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.{Notifications, Repo}
  alias Dawarich.Notifications.Events

  def read(owner, %{read_at: nil} = notification) do
    if Enum.any?(
         [notification.title, notification.content, notification.kind],
         &(is_nil(&1) or (is_binary(&1) and String.trim(&1) == ""))
       ),
       do: raise(Notifications.Invalid)

    now = NaiveDateTime.utc_now()

    mutate(owner, fn ->
      from(n in "notifications",
        where: n.id == ^notification.id and n.user_id == ^owner and is_nil(n.read_at)
      )
      |> Repo.update_all(set: [read_at: now, updated_at: now])
    end)

    %{notification | read_at: now}
  end

  def read(_, notification), do: notification

  def mark_all(owner),
    do:
      mutate(owner, fn ->
        from(n in "notifications", where: n.user_id == ^owner and is_nil(n.read_at))
        |> Repo.update_all(set: [read_at: NaiveDateTime.utc_now()])
      end)

  def delete(owner, id),
    do:
      mutate(owner, fn ->
        from(n in "notifications", where: n.user_id == ^owner and n.id == ^id)
        |> Repo.delete_all()
      end)

  def delete_all(owner),
    do:
      mutate(owner, fn ->
        from(n in "notifications", where: n.user_id == ^owner) |> Repo.delete_all()
      end)

  defp mutate(owner, effect) do
    {:ok, result} =
      Repo.transaction(fn ->
        {count, _} = result = effect.()
        if count > 0, do: Events.enqueue(Repo, owner)
        result
      end)

    result
  end
end
