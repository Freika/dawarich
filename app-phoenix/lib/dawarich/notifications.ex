defmodule Dawarich.Notifications do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.Repo

  @per_page 20
  @kinds %{0 => "info", 1 => "warning", 2 => "error"}
  @max_id 9_223_372_036_854_775_807

  def page(user_id, page) do
    offset = (page - 1) * @per_page
    owned = from(n in "notifications", where: n.user_id == ^user_id)
    count = owned |> select([n], count(n.id)) |> Repo.one()

    %{
      notifications:
        owned
        |> order_by([n], desc: n.created_at)
        |> limit(@per_page)
        |> offset(^offset)
        |> rows(),
      total_pages: div(count + @per_page - 1, @per_page),
      unread_on_page?:
        owned
        |> where([n], is_nil(n.read_at))
        |> offset(^offset)
        |> limit(1)
        |> select([n], 1)
        |> Repo.one() == 1
    }
  end

  def get(user_id, id) when is_integer(id) and id > 0 and id <= @max_id,
    do:
      from(n in "notifications", where: n.user_id == ^user_id and n.id == ^id)
      |> rows()
      |> List.first()

  def get(_user_id, _id), do: nil

  def mark_read(user_id, %{read_at: nil} = notification) do
    now = NaiveDateTime.utc_now()

    from(n in "notifications",
      where: n.id == ^notification.id and n.user_id == ^user_id and is_nil(n.read_at)
    )
    |> Repo.update_all(set: [read_at: now, updated_at: now])

    %{notification | read_at: now}
  end

  def mark_read(_user_id, notification), do: notification

  def mark_all_read(user_id),
    do:
      from(n in "notifications", where: n.user_id == ^user_id and is_nil(n.read_at))
      |> Repo.update_all(set: [read_at: NaiveDateTime.utc_now()])

  def delete(user_id, id),
    do:
      from(n in "notifications", where: n.user_id == ^user_id and n.id == ^id)
      |> Repo.delete_all()

  def delete_all(user_id),
    do: from(n in "notifications", where: n.user_id == ^user_id) |> Repo.delete_all()

  defp rows(query) do
    query
    |> select([n], %{
      id: n.id,
      title: n.title,
      content: n.content,
      kind: n.kind,
      read_at: n.read_at,
      created_at: n.created_at
    })
    |> Repo.all()
    |> Enum.map(&%{&1 | kind: @kinds[&1.kind]})
  end
end
