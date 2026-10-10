import { AchievementUnlocks } from "./achievement_unlocks.js"
import { ArchiveChecksum } from "./archive_checksum.js"
import { ChangelogWidget } from "./changelog_widget.js"
import { Clipboard } from "./clipboard.js"
import { CredentialQr } from "./credential_qr.js"
import { CredentialValue } from "./credential_value.js"
import { Dismissible } from "./dismissible.js"
import { EmojiPicker } from "./emoji_picker.js"
import { FamilyConfirm } from "./family_confirm.js"
import { FamilyInvitationClipboard } from "./family_invitation_clipboard.js"
import { FamilyMap } from "./family_map.js"
import { MapMatchingDemo } from "./map_matching_demo.js"
import { ScrollIntoView } from "./scroll_into_view.js"
import { SharedMap } from "./shared_map.js"
import {
  SharingDialog,
  SharingPhrase,
  SharingReveal,
} from "./sharing_controls.js"

export const hooks = {
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
  ScrollIntoView,
}
