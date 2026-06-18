# AGENTS.md

## Project

Glaze is a macOS Apple Silicon video player that prepares subtitles before playback. The core product value is local, privacy-respecting AI subtitle generation and Korean-friendly subtitle/translation workflows for personal video libraries.

Korean product name: `글레이즈`  
Global product name: `Glaze`

## Required Working Principle

Every meaningful task must follow this loop:

1. Understand the relevant product/design/user-flow context.
2. Implement the change.
3. Verify the change.
4. Update the related documentation.
5. Commit the verified work to Git.
6. Push to GitHub.

Do not treat the MVP as disposable. The macOS MVP is the reference implementation for future iOS/iPadOS, Android, Windows, and browser extension work.

## Documentation Rules

When code or product behavior changes, update the matching docs:

- Product direction: `docs/02_product_direction.md`
- AI subtitle workflow: `docs/03_ai_subtitle_workflow.md`
- Development plan: `docs/04_product_development_plan.md`
- Browser extension strategy: `docs/05_browser_extension_strategy.md`
- Platform/global expansion: `docs/06_platform_global_expansion_plan.md`
- MVP decisions: `docs/07_mvp_scope_and_decisions.md`
- Brand/naming: `docs/08_brand_naming_strategy.md`
- Monetization filtering: `docs/09_monetization_feature_tiers.md`
- Development checklist: `docs/10_development_start_checklist.md`
- UI/design direction: `docs/11_ui_reference_design_direction.md`
- Service text inventory: `docs/12_service_text_inventory.md`
- User flows: `docs/13_user_flows.md`
- Working principles: `docs/14_working_principles.md`

For new user-facing text, update `docs/12_service_text_inventory.md` and the localization files together.

For new or changed UX behavior, update `docs/13_user_flows.md`.

For implementation progress, update `docs/10_development_start_checklist.md`.

## UX/Product Rules

- The video viewing experience comes first.
- AI work starts only after explicit user action.
- Subtitle absence should be visible but not disruptive.
- Save-location prompts appear when subtitle generation is requested, not during basic playback.
- Korean and English UI are the initial required languages.
- If the system language is unsupported, fall back to English.
- Keep macOS-native behavior and visual density.
- Use user-result wording over technical AI jargon.

## Current Technical Baseline

- Swift Package project
- SwiftUI app
- macOS 15 minimum
- Apple Silicon first
- AVFoundation/AVKit first
- FFmpeg is a near-term post-Player-MVP validation task
- Localized strings live under `Sources/Glaze/Resources`

Build command:

```bash
swift build
```

## Git Rules

- Keep `main` usable.
- Commit feature-sized changes.
- Prefer separate commits for documentation-only and code changes unless they are tightly coupled.
- Push completed work to `origin/main`.
- Do not leave verified work uncommitted.

## Current GitHub Remote

```text
https://github.com/Edwin-space/glaze.git
```

## Agent Startup Checklist

At the start of a new session:

1. Read this `AGENTS.md`.
2. Check `git status --short --branch`.
3. Review the relevant docs for the requested task.
4. Continue the implement → verify → document → commit → push loop.
