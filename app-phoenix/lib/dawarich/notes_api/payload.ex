defmodule Dawarich.NotesApi.Payload do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}

  @keys ~w(id title body latitude longitude attachable_type attachable_id date noted_at created_at updated_at)

  def rows(where, params, tail \\ "") do
    sql =
      "SELECT n.id, n.title, n.body, ST_Y(n.lonlat::geometry), ST_X(n.lonlat::geometry), n.attachable_type, " <>
        "n.attachable_id, n.noted_at::date::text, #{RailsTime.sql("n.noted_at", 3)}, " <>
        "#{RailsTime.sql("n.created_at", 3)}, #{RailsTime.sql("n.updated_at", 3)}, n.noted_at " <>
        "FROM notes n WHERE #{where}#{tail}"

    Repo.query!(sql, params).rows
  end

  def term(row), do: {:object, Enum.zip(@keys, row)}
end
