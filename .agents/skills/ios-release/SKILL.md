---
name: ios-release
description: Generates a comprehensive iOS App Store release readiness checklist by scanning the codebase for TODO/FIXME/HACK comments and analyzing build quality, then saves the checklist to production/releases/. Use when the user is preparing an iOS app for release, submitting to App Store, cutting a release branch, or checking release readiness. Also use when the user mentions release checklist, pre-release check, app store submission prep, or wants to assess if the app is ready to ship.
---

# iOS Release

Generates a release readiness checklist for iOS apps. Scan the codebase for health
markers, then produce a structured checklist covering build, quality, platform,
store, and launch readiness.

## Step 1 — Load project context

Read these files to understand the project:

1. `README.md` (or `README.markdown`, `README.org`)
2. Any file matching `docs/*.md` — especially `docs/ios_app_store_release_checklist.md` if present
3. Any `CLAUDE.md` at the project root or in `kitchen/CLAUDE.md`, `worker/CLAUDE.md`, etc.
4. Read the Xcode project file (`*.xcodeproj/project.pbxproj`) to extract:
   - `MARKETING_VERSION` (the version string)
   - `CURRENT_PROJECT_VERSION` (the build number)
   - `PRODUCT_BUNDLE_IDENTIFIER`
   - Deployment target (`IPHONEOS_DEPLOYMENT_TARGET`)

From this context, determine:
- App name
- Current version + build
- Bundle ID
- iOS deployment target
- Backend/service dependencies
- Any existing release process notes

If the project has `docs/ios_app_store_release_checklist.md`, use it as the authoritative
template for sections marked with `[*]` below. The generated checklist should include
all items from that existing document where applicable, augmented with the codebase
scan results.

## Step 2 — Scan codebase for outstanding issues

Run these scans in the project root. Scan only the main source directories (not
Pods, build, DerivedData, node_modules, .build, or package caches).

### TODO / FIXME / HACK counts

Use Grep to count and locate every comment matching these patterns:

- `TODO[:\s]` — feature gaps, unfinished work
- `FIXME[:\s]` — known bugs, broken behavior (potential blockers)
- `HACK[:\s]` — workarounds that need review before release

For each, capture:
- Total count
- File path and line number
- The comment text

### Additional scan (optional but recommended)

- `@available(*, deprecated` usages — deprecated API calls
- `#warning(` — compiler warnings embedded in code
- `fatalError(` or `preconditionFailure(` — crash points that could hit users

### Summarize

Group findings by severity:
- **Blockers**: FIXME comments, HACK comments in critical paths (auth, data, payments)
- **Before-release**: TODO comments in user-facing flows, deprecated API usage
- **Can-defer**: TODO comments in non-critical paths, internal tooling

## Step 3 — Determine version

Get the version from the project context loaded in Step 1. If multiple version
strings exist (e.g., different targets), use the main app target's
`MARKETING_VERSION`. If it cannot be found, ask the user.

## Step 4 — Generate the checklist

Compose the checklist as a single Markdown document. The structure below is the
template. When the project has an existing `ios_app_store_release_checklist.md`,
merge its specific items into the matching sections rather than duplicating.

### Checklist template

```markdown
# Release Checklist: [App Name] [Version]
**Generated:** [Date]
**Bundle ID:** [Bundle ID]
**iOS Target:** [Deployment Target]

---

## Codebase Health

- TODO count: [N]
- FIXME count: [N]  
- HACK count: [N]

### Top TODOs
[List up to 5 most important TODOs by file and line. If >5, note "and N more"]

### All FIXMEs (potential blockers)
[Every FIXME with file:line and comment text. If zero, write "None — good."]

### All HACKs (need review)
[Every HACK with file:line and comment text. If zero, write "None — good."]

---

## Build Verification

- [ ] Clean build succeeds: Release configuration, device target
- [ ] No compiler warnings (zero-warning policy)
- [ ] All assets included and loading correctly
- [ ] Build version correctly set to [version] (build [build number])
- [ ] Build is reproducible from tagged commit
- [ ] Release archive succeeds in Xcode
- [ ] Archive passes processing in App Store Connect

---

## Product Completeness

- [ ] Primary user flows complete and tested end-to-end
- [ ] Empty states present for all list/detail views
- [ ] Loading states present for all async operations
- [ ] Error states handled with user-facing messages
- [ ] No debug data, placeholder text, or test content in release build
- [ ] All placeholder assets replaced with final versions
- [ ] All unfinished features gated behind feature flags or removed

---

## Permissions & Privacy

- [ ] All required device permissions have usage description strings in Info.plist
  - Camera: NSCameraUsageDescription
  - Photo Library: NSPhotoLibraryUsageDescription
  - Microphone (if used): NSMicrophoneUsageDescription
  - Location (if used): NSLocationWhenInUseUsageDescription
- [ ] Permissions requested only when needed (not all at launch)
- [ ] Permission denial paths handled gracefully
- [ ] Privacy policy URL accessible and accurate
- [ ] App Privacy labels filled in App Store Connect
- [ ] No third-party tracking without disclosure
- [ ] Account deletion path available (if account creation exists)

---

## App Store Metadata

- [ ] App name final
- [ ] Subtitle final
- [ ] Keywords researched and set
- [ ] Description (short + long) proofread
- [ ] Screenshots up to date for all required device sizes
- [ ] App icon (1024x1024) final, visible in all modes (light/dark/tinted)
- [ ] Support URL accessible
- [ ] Privacy policy URL accessible
- [ ] Age rating questionnaire completed
- [ ] Export compliance completed
- [ ] Pricing configured for all regions
- [ ] Review notes prepared (demo account, test flow, special features)

---

## Quality Gates

- [ ] Unit tests pass
- [ ] UI tests pass (if present)
- [ ] Manual QA pass on minimum-supported device
- [ ] Manual QA pass on largest-supported device
- [ ] Dark Mode visuals verified
- [ ] Dynamic Type (accessibility sizes) verified — no clipped text
- [ ] VoiceOver navigates all primary screens
- [ ] Offline / weak-network behavior acceptable
- [ ] Cold start, background, foreground transitions correct
- [ ] No crashes, ANRs, or visible frame drops on release build
- [ ] Battery usage within acceptable range
- [ ] Memory usage stable over extended use

---

## TestFlight

- [ ] Build uploaded to App Store Connect
- [ ] Build passed processing
- [ ] Internal testers added
- [ ] Beta App Review completed (if using external testers)
- [ ] Feedback from internal testers resolved or documented
- [ ] Beta release notes written

---

## Launch Readiness

- [ ] Analytics / telemetry receiving data
- [ ] Crash reporting configured and dashboard accessible
- [ ] On-call / support plan in place for first 72 hours
- [ ] Rollback plan documented
- [ ] Announcements drafted (social, blog, etc.)
- [ ] Third-party license attributions complete
- [ ] Credits accurate and final

---

## Go / No-Go

**Status:** [READY / NOT READY]

**Blockers:**
[List of specific blocking items. If none, say "None."]

**Sign-offs:**
- [ ] Developer
- [ ] QA (if applicable)
- [ ] Product Owner (if applicable)
```

## Step 5 — Present the summary

After generating the checklist, present a concise summary to the user:

```
## Release Checklist Generated: [Version]

Total checklist items: [N]
Known blockers: [M] (FIXME: X, HACK: Y)
Critical TODOs: [Z]

May I write this to `production/releases/release-checklist-[version].md`?
```

Wait for the user's confirmation before writing.

## Step 6 — Write the file

If the user agrees, create the directory `production/releases/` if it doesn't
exist, then write the checklist. After writing, confirm the file path.

If the user asks for changes or additions to a specific section, apply them and
re-present.

## Notes

- This skill works for any iOS project, not just the current one. Adapt the scan
  paths and project file parsing accordingly.
- If the project isn't iOS (no `.xcodeproj` or `.xcworkspace`), skip the Xcode
  parsing and ask the user for the version number.
- The generated checklist is a snapshot. The user should re-run this skill
  periodically as the release date approaches to get updated codebase health
  stats.
- Do not remove sections from the template unless they genuinely don't apply to
  the project (e.g., TestFlight if the project has no Apple Developer account).
  When in doubt, keep the section and mark items as "N/A" with a reason.
