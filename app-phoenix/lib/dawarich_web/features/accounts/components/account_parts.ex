defmodule DawarichWeb.AccountParts do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil
  attr :errors, :list, default: []
  attr :submitted_email, :string, default: nil

  def profile(assigns), do: DawarichWeb.AccountProfile.profile(assigns)

  attr :locale, :string, required: true
  attr :upload, :map, required: true
  attr :checksums, :map, required: true

  def import_dialog(assigns), do: DawarichWeb.AccountImport.dialog(assigns)

  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :trial, :boolean, required: true
  attr :trial_at, :map, default: nil
  attr :auto_converting, :boolean, required: true
  attr :manager, :string, default: nil
  attr :subscription, :string, default: nil
  attr :points, :integer, required: true

  def plan_cards(assigns), do: DawarichWeb.PlanCards.plan_cards(assigns)

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :self_hosted, :boolean, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil

  def data_tools(assigns), do: DawarichWeb.DangerZone.data_tools(assigns)
end
