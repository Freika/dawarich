defmodule DawarichWeb.AchievementSharingControls do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  attr :set, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  def controls(assigns) do
    ~H"""
    <a href={"/achievements/" <> @set["key"] <> "/sharing"} class="btn btn-sm btn-primary">{t(
      @locale,
      "achievements.modal.share",
      %{}
    )}</a>
    <a
      class="btn btn-sm btn-outline"
      hidden={!@set["sharing_enabled"] && "hidden"}
      data-card-modal-target="publicLink"
      href={
        if(@set["sharing_enabled"], do: "/shared/achievements/" <> @set["sharing_uuid"], else: "#")
      }
    ><.icon name="external-link" class="w-4 h-4" aria_hidden />{t(
      @locale,
      "achievements.ui.public_link",
      %{}
    )}</a>
    """
  end
end
