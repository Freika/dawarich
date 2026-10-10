defmodule Dawarich.Notifications.Native do
  @moduledoc false
  alias Dawarich.{Notifications, Repo}
  alias Dawarich.Accounts.NativeAccess

  def page(scope, page) do
    with {:ok, current} <- NativeAccess.admit(scope),
         do: {:ok, Notifications.page(current.user.id, page)}
  end

  def unread(scope) do
    with {:ok, current} <- NativeAccess.admit(scope),
         do: {:ok, Dawarich.Navbar.unread(current.user.id)}
  end

  def open(scope, id) do
    write(scope, fn current ->
      id = id(id)
      lock(current.user.id, id)

      case Notifications.get(current.user.id, id) do
        nil -> Repo.rollback(:not_found)
        notification -> Notifications.mark_read(current.user.id, notification)
      end
    end)
  end

  def mark_all_read(scope), do: write(scope, &Notifications.mark_all_read(&1.user.id))
  def delete_all(scope), do: write(scope, &Notifications.delete_all(&1.user.id))

  def delete(scope, id) do
    write(scope, fn current ->
      case Notifications.delete(current.user.id, id(id)) do
        {0, _} -> Repo.rollback(:not_found)
        _ -> :deleted
      end
    end)
  end

  defp write(scope, effect) do
    with {:ok, _} <- NativeAccess.admit(scope) do
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM users WHERE id=$1 FOR SHARE", [scope.user.id], log: false)

        case NativeAccess.admit(scope) do
          {:ok, current} -> effect.(current)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp lock(user_id, id),
    do:
      Repo.query!(
        "SELECT id FROM notifications WHERE user_id=$1 AND id=$2 FOR UPDATE",
        [user_id, id], log: false)

  defp id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id

  defp id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} -> id(value)
      _ -> 0
    end
  end

  defp id(_), do: 0
end
