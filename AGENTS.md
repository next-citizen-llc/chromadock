# ChromaDock

Native macOS utility. Do not sandbox the app. Do not add agent authorship
to commits, tags, or GitHub metadata.

- Product name: ChromaDock
- Bundle ID: `llc.nextcitizen.ChromaDock`
- Divider helpers: `llc.nextcitizen.ChromaDock.line.N` at `~/Library/Application Support/ChromaDock/Lines/Line N.app` (legacy `.divider.N` tiles and the old `Dividers/` directory are still recognized and replaced)
- Build: `./scripts/build.sh`
- Disk image: `./scripts/package-dmg.sh`

## Thread-Aware Email Sending (standing operator rule)

- Before composing or sending any email on the operator's behalf, first scan
  the operator's mailboxes for an existing thread on the topic.
- Default to replying within the existing thread, from the same address the
  thread lives under, so threading and recipient expectations hold.
- Err on the side of asking, always: when in any doubt, present the found
  thread(s) and ask whether the message should be a reply to an existing
  thread or a new email — before any send.
- This composes with, and never replaces, explicit send approval.
