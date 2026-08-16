# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## toolbar-click-does-nothing — Transient chooser closes during LSUIElement LaunchServices startup
- **Date:** 2026-08-16
- **Error patterns:** toolbar icon, clicking, no visible result, no error, no permission prompt, chooser
- **Root cause:** A synchronous `NSMenu.popUp` was the app's only UI/event loop during LSUIElement LaunchServices activation; AppKit created the popup but ended menu tracking before the chooser became stably interactive, causing the app to return as if cancelled.
- **Fix:** Replaced the transient menu with a retained key-capable `NSPanel` presented after `applicationDidFinishLaunching` while `NSApplication.run` owns the event loop, with explicit selection, Escape, outside-click completion, and screen-edge positioning. Verification was artifact-level; the stale Finder toolbar binding did not live-exercise the new panel.
- **Files changed:** Sources/OpenInAgent/AgentMenuController.swift, Tests/OpenInAgentTests/AgentMenuControllerTests.swift
---
