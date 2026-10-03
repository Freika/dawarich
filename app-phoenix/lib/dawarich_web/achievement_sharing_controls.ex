defmodule DawarichWeb.AchievementSharingControls do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  attr :set, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  def controls(assigns) do
    ~H"""
    <form
      hidden={@set["sharing_enabled"] && "hidden"}
      data-card-modal-target="createForm"
      data-action="submit->card-modal#createPublicLink"
      data-turbo="false"
      class="button_to"
      method="post"
      action={"/achievements/"<>@set["key"]<>"/toggle_sharing"}
    >
      <input type="hidden" name="_method" value="patch" /><button
        class="btn btn-sm btn-primary"
        type="submit"
      ><.icon name="share" class="w-4 h-4" aria_hidden />{t(
        @locale,
        "achievements.ui.enable_sharing",
        %{}
      )}</button><input type="hidden" name="authenticity_token" value={@csrf} /><input
        type="hidden"
        name="enabled"
        value="true"
      />
    </form>
    <form
      hidden={!@set["sharing_enabled"] && "hidden"}
      data-card-modal-target="disableForm"
      data-turbo="false"
      class="button_to"
      method="post"
      action={"/achievements/"<>@set["key"]<>"/toggle_sharing"}
    >
      <input type="hidden" name="_method" value="patch" /><button
        class="btn btn-sm btn-ghost"
        type="submit"
      ><.icon name="lock" class="w-4 h-4" aria_hidden />{t(
        @locale,
        "achievements.ui.disable_sharing",
        %{}
      )}</button><input type="hidden" name="authenticity_token" value={@csrf} /><input
        type="hidden"
        name="enabled"
        value="false"
      />
    </form>
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
