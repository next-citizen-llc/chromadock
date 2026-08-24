# Contributing to ChromaDock

Created by [Tristan Springmeyer (`@tristan-nextcz`)](https://github.com/tristan-nextcz).
The canonical repository is owned by [Next Citizen LLC](https://github.com/next-citizen-llc).

## License of contributions

By submitting a contribution (code, docs, tests, design, or other material) you
agree that:

1. You license your contribution to Next Citizen LLC under the MIT License in
   `LICENSE`.
2. You have the right to grant that license.
3. Next Citizen LLC may relicense the combined work, including your
   contribution, for future versions, add-ons, or commercial distributions.

This is how the project stays free to use now while remaining able to offer
additional licenses later. If you cannot agree to that, please do not submit
the contribution.

## Practical notes

- Target macOS 14 or later, Apple silicon first.
- Do not sandbox the app: it must write Dock preferences.
- Do not add agent or assistant authorship to commits, PRs, or releases.
- Keep secrets, personal Dock backups, and machine-local paths out of the repo.
