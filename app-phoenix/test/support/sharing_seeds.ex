defmodule Dawarich.Test.SharingSeeds do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  @dir Path.expand("../fixtures/sharing", __DIR__)

  def fixture(name), do: @dir |> Path.join(name) |> File.read!() |> Jason.decode!()

  def page(name), do: @dir |> Path.join("pages/#{name}") |> File.read!()

  def load!(now \\ NaiveDateTime.utc_now()) do
    seed = fixture("seed.json")
    {:ok, anchor, 0} = DateTime.from_iso8601(fixture("pages.json")["now"])
    shift = NaiveDateTime.diff(now, DateTime.to_naive(anchor), :microsecond)

    for user <- seed["users"],
        do:
          RailsUser.insert!(%{
            id: user["id"],
            email: user["email"],
            settings: user["settings"],
            api_key: user["api_key"]
          })

    Repo.insert_all("shared_links", Enum.map(seed["shared_links"], &row(&1, shift)))
    seed
  end

  def link!(attrs) do
    stamp = NaiveDateTime.utc_now()

    row =
      Map.merge(
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          user_id: 9901,
          resource_type: 3,
          name: "Link",
          settings: %{},
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )

    Repo.insert_all("shared_links", [row])
    Ecto.UUID.load!(row.id)
  end

  def view_count(id) do
    %{rows: [[count]]} =
      Repo.query!("SELECT view_count FROM shared_links WHERE id = $1::text::uuid", [id])

    count
  end

  defp row(link, shift) do
    stamp = at(link["created_at"], shift)

    %{
      id: Ecto.UUID.dump!(link["id"]),
      user_id: link["user_id"],
      resource_type: link["resource_type"],
      resource_id: link["resource_id"],
      name: link["name"],
      magic_phrase: link["magic_phrase"],
      settings: link["settings"],
      expires_at: at(link["expires_at"], shift),
      revoked_at: at(link["revoked_at"], shift),
      created_at: stamp,
      updated_at: stamp
    }
  end

  defp at(nil, _shift), do: nil

  defp at(text, shift) do
    {:ok, time, 0} = DateTime.from_iso8601(text)
    time |> DateTime.to_naive() |> NaiveDateTime.add(shift, :microsecond)
  end
end
