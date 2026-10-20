import { NativeHeatmap } from "../charts/heatmap.js"
import { NativeChart } from "../charts/hook.js"
import { MapMatchingDemo } from "../demo/hook.js"
import { RichText } from "../editor/hook.js"
import { InsightsYearMap } from "../insights/year_map_hook.js"
import { FamilyHook } from "../map/hooks/family.js"
import { MapHook } from "../map/hooks/map.js"
import { MapPreview } from "../map/hooks/map_preview.js"
import { PublicMap } from "../map/hooks/public_map.js"
import { TripHook } from "../map/hooks/trip.js"
import { FamilyMap, SharedMap } from "../map/shared/lazy_maps.js"
import { OnboardingHook } from "../onboarding/hook.js"
import { PosterStudio } from "../poster/hook.js"
import { VideoStudio } from "../video/hook.js"
import { AchievementUnlocks } from "./achievement_unlocks.js"
import { ArchiveChecksum } from "./archive_checksum.js"
import { AreaPreview } from "./area_preview.js"
import { ChangelogWidget } from "./changelog_widget.js"
import { Clipboard } from "./clipboard.js"
import { CredentialQr } from "./credential_qr.js"
import { CredentialValue } from "./credential_value.js"
import { Dismissible } from "./dismissible.js"
import { EmojiPicker } from "./emoji_picker.js"
import { FamilyConfirm } from "./family_confirm.js"
import { FamilyInvitationClipboard } from "./family_invitation_clipboard.js"
import { LayerToggle } from "./layer_toggle.js"
import { OrdinaryDialog } from "./ordinary_dialog.js"
import { PublicGallery } from "./public_gallery.js"
import { PlaceDraft } from "./place_draft.js"
import { ScrollIntoView } from "./scroll_into_view.js"
import {
  SharingDialog,
  SharingPhrase,
  SharingReveal,
} from "./sharing_controls.js"

export const hooks = {
  PublicGallery,
  InsightsYearMap,
  OrdinaryDialog,
  PlaceDraft,
  LayerToggle,
  SharedMap,
  SharingDialog,
  SharingPhrase,
  SharingReveal,
  FamilyMap,
  FamilyConfirm,
  FamilyInvitationClipboard,
  AchievementUnlocks,
  ArchiveChecksum,
  AreaPreview,
  ChangelogWidget,
  Clipboard,
  CredentialQr,
  CredentialValue,
  Dismissible,
  EmojiPicker,
  Map: MapHook,
  Onboarding: OnboardingHook,
  MapPreview,
  PublicMap,
  PosterStudio,
  VideoStudio,
  Family: FamilyHook,
  Trip: TripHook,
  MapMatchingDemo,
  NativeChart,
  NativeHeatmap,
  RichText,
  ScrollIntoView,
}
