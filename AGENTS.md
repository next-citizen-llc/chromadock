# ChromaDock

Native macOS utility. Do not sandbox the app. Do not add agent authorship
to commits, tags, or GitHub metadata.

- Product name: ChromaDock
- Bundle ID: `llc.nextcitizen.ChromaDock`
- Divider helpers: `llc.nextcitizen.ChromaDock.line.N` at `~/Library/Application Support/ChromaDock/Lines/Line N.app` (legacy `.divider.N` tiles and the old `Dividers/` directory are still recognized and replaced)
- Build: `./scripts/build.sh`
- Disk image: `./scripts/package-dmg.sh`
