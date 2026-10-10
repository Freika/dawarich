import { AchievementUnlocks } from "./achievement_unlocks.js"
import { ArchiveChecksum } from "./archive_checksum.js"
import { ChangelogWidget } from "./changelog_widget.js"
import { NativeChart } from "./chart.js"
import { Clipboard } from "./clipboard.js"
import { CredentialQr } from "./credential_qr.js"
import { CredentialValue } from "./credential_value.js"
import { Dismissible } from "./dismissible.js"
import { EmojiPicker } from "./emoji_picker.js"
import { FamilyConfirm } from "./family_confirm.js"
import { FamilyInvitationClipboard } from "./family_invitation_clipboard.js"
import { NativeHeatmap } from "./heatmap.js"
import { FamilyMap, SharedMap } from "./lazy_maps.js"
import { MapMatchingDemo } from "./map_matching_demo.js"
import { OrdinaryDialog } from "./ordinary_dialog.js"
import { PlaceDraft } from "./place_draft.js"
import { RichText } from "./rich_text.js"
import { ScrollIntoView } from "./scroll_into_view.js"
import {
  SharingDialog,
  SharingPhrase,
  SharingReveal,
} from "./sharing_controls.js"

export const hooks = {
  OrdinaryDialog,
  PlaceDraft,
  SharedMap,
  SharingDialog,
  SharingPhrase,
  SharingReveal,
  FamilyMap,
  FamilyConfirm,
  FamilyInvitationClipboard,
  AchievementUnlocks,
  ArchiveChecksum,
  ChangelogWidget,
  Clipboard,
  CredentialQr,
  CredentialValue,
  Dismissible,
  EmojiPicker,
  MapMatchingDemo,
  NativeChart,
  NativeHeatmap,
  RichText,
  ScrollIntoView,
}
