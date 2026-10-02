defmodule Dawarich.Visits.Sql do
  @moduledoc false

  def machine(v),
    do:
      "#{v}.deleted_at IS NULL AND #{v}.status != 2 AND #{v}.status = 0 AND #{v}.import_id IS NULL " <>
        "AND #{v}.demo = false AND #{v}.id NOT IN " <>
        "(SELECT notes.attachable_id FROM notes WHERE notes.attachable_type = 'Visit')"

  def anchor(v, uid),
    do: "#{v}.id NOT IN (SELECT m.id FROM visits m WHERE m.user_id = #{uid} AND #{machine("m")})"
end
