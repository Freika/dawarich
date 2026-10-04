defmodule Dawarich.Posters.PersistenceTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Posters.Persistence

  @tag mutation: "title"
  test "poster create stores whitelist and localized default without title fallback mutation" do
    id = user!()

    params = %{
      "name" => " ",
      "title" => "",
      "lat" => "1.2",
      "lon" => "3.4",
      "route_width" => "2",
      "route_fill" => "0",
      "layout" => "ignored",
      "user_id" => "0"
    }

    assert {:ok, poster} = Persistence.create(params, %{id: id}, "de")

    assert [["Unbenanntes Poster", 0, settings, ^id]] =
             Repo.query!("SELECT name, status, settings, user_id FROM posters WHERE id = $1", [
               poster
             ]).rows

    assert settings == Map.take(params, ~w(title lat lon route_width route_fill))

    assert {:ok, named} =
             Persistence.create(%{"name" => "Gallery", "title" => ""}, %{id: id}, "en")

    assert [["Gallery", %{"title" => ""}]] =
             Repo.query!("SELECT name, settings FROM posters WHERE id = $1", [named]).rows
  end

  @tag mutation: "atomic"
  test "poster and command commit or roll back together" do
    id = user!()
    assert {:ok, poster} = Persistence.create(%{}, %{id: id}, "en")

    assert commands() == [
             ["posters.created", %{"poster_id" => poster, "user_id" => id, "locale" => "en"}]
           ]

    Repo.query!("DROP TABLE phoenix.rails_commands")
    assert {:error, _} = Persistence.create(%{}, %{id: id}, "en")
    assert [[1]] = Repo.query!("SELECT count(*) FROM posters WHERE user_id = $1", [id]).rows
    Dawarich.Jobs.Ownership.put!(Repo, "command:posters.create", :oban)
    Repo.query!("DROP TABLE public.job_outbox")
    assert {:error, _} = Persistence.create(%{}, %{id: id}, "de")
    assert [[1]] = Repo.query!("SELECT count(*) FROM posters WHERE user_id = $1", [id]).rows
  end
end
