defmodule Dawarich.Notifications do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.{Repo, UserTimeZone}

  defmodule Invalid do
    defexception message: "Notification validation failed", plug_status: 422
  end

  @per_page 20
  @kind_names %{0 => "info", 1 => "warning", 2 => "error"}
  @kind_codes %{info: 0, warning: 1, error: 2}
  @max_id 9_223_372_036_854_775_807
  @year_bucket_days 364

  def kind_name(kind), do: Map.get(@kind_names, kind)

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
    if Enum.any?(
         [notification.title, notification.content, notification.kind],
         &(is_nil(&1) or (is_binary(&1) and String.trim(&1) == ""))
       ),
       do: raise(Invalid)

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

  def localize(notifications, settings, now) do
    cutoff = now |> DateTime.to_naive() |> NaiveDateTime.add(-@year_bucket_days * 86_400)
    old = for %{created_at: at} <- notifications, NaiveDateTime.before?(at, cutoff), do: at
    local = if old == [], do: %{}, else: zoned(old, settings)
    Enum.map(notifications, &Map.update!(&1, :created_at, fn at -> Map.get(local, at, at) end))
  end

  defp zoned(times, settings) do
    %{rows: rows} =
      UserTimeZone.query!(
        """
        SELECT extract(epoch FROM ((t AT TIME ZONE 'UTC') AT TIME ZONE z.name) - t)::int, z.name
        FROM unnest($1::timestamp[]) WITH ORDINALITY AS u(t, i), z
        ORDER BY i
        """,
        [times],
        settings
      )

    times
    |> Enum.zip(rows)
    |> Map.new(fn {at, [offset, name]} ->
      local = DateTime.from_naive!(NaiveDateTime.add(at, offset), "Etc/UTC")
      {at, %{local | time_zone: name, zone_abbr: name, utc_offset: offset}}
    end)
  end

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
    |> Enum.map(&%{&1 | kind: @kind_names[&1.kind]})
  end

  def create!(repo, user_id, kind, title, content, now \\ NaiveDateTime.utc_now()) do
    if repo.in_transaction?() do
      insert_notification(repo, user_id, kind, title, content, now)
    else
      {:ok, id} =
        repo.transaction(fn -> insert_notification(repo, user_id, kind, title, content, now) end)

      id
    end
  end

  defp insert_notification(repo, user_id, kind, title, content, now) do
    %{rows: [[id]]} =
      repo.query!(
        "INSERT INTO notifications (user_id, kind, title, content, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5) RETURNING id",
        [user_id, Map.fetch!(@kind_codes, kind), title, content, now],
        log: false
      )

    repo.query!("INSERT INTO phoenix.notification_events (notification_id) VALUES ($1)", [id],
      log: false
    )

    id
  end
end
