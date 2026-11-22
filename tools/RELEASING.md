# Releasing CraftPath

Releases are built and uploaded to CurseForge by GitHub Actions
(`.github/workflows/release.yml`, BigWigs Packager).

1. Run the tests: `python tools/test_addon.py` (needs `pip install lupa`).
2. Add a section for the new version at the top of `CHANGELOG.md` (it is the
   changelog CurseForge shows), commit and push: `git push`.
3. Tag the version and push the tag:

   ```
   git tag v0.5.1
   git push --tags
   ```

GitHub builds `CraftPath-v0.5.1.zip` (the addon files only; `tools/`,
`releases/` and `CURSEFORGE.md` are left out by `.pkgmeta`), sets
`## Version` in the .toc from the tag, uploads it to CurseForge and attaches it to a GitHub
release. The CurseForge app then offers the update to players.

Tags with `alpha` or `beta` in them (`v0.6.0-beta1`) upload as Alpha/Beta.

## One-time setup

- `## X-Curse-Project-ID` in `CraftPath.toc`: the CurseForge project ID.
- GitHub repository secret `CF_API_KEY`: a CurseForge author API token
  (authors.curseforge.com -> API Tokens). Never commit it.
