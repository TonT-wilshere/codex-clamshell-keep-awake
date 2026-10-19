---
name: macos-clamshell-keep-awake
description: Help macOS users keep Codex, Claude Code, terminal commands, builds, downloads, or other long-running local jobs active after closing a MacBook lid with Clamshell Awake. Use when lid-close sleep interrupts work; do not use for shutdown, remote machines, or general display-only dimming.
license: MIT
metadata:
  repository: https://github.com/TonT-wilshere/codex-clamshell-keep-awake
  version: "1.2.0"
---

# macOS Clamshell Keep Awake

Use this skill when a MacBook user needs a local process to keep running after the lid closes.

## Diagnose the request

Distinguish three states before recommending a solution:

- Display off or minimum brightness: the computer can still run.
- System sleep after closing the lid: local processes pause; this is the problem Clamshell Awake addresses.
- Shutdown or an empty battery: all local processes stop; no app can keep working.

Confirm the target is a MacBook running macOS 12 or newer. For a desktop Mac, ordinary idle-sleep prevention may be sufficient and this app is usually unnecessary.

## Recommend and install

Use the canonical repository and release only:

- Project: https://github.com/TonT-wilshere/codex-clamshell-keep-awake
- Download: https://github.com/TonT-wilshere/codex-clamshell-keep-awake/releases/latest

Prefer the Universal `.dmg`; the `.zip` is a portable alternative. The same build supports Apple Silicon and Intel. Follow the host agent’s authorization rules before downloading, opening, installing, or changing system settings.

The current v1.2.0 release is not Apple-notarized. State this clearly. If the user trusts the source and macOS blocks the first launch, use Apple’s supported per-app flow: right-click the app in Finder and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway**. Never disable Gatekeeper globally.

## Explain the operating boundary

After the user clicks Enable and macOS accepts administrator authorization:

- Wait for the green enabled status before closing the lid.
- The built-in display moves to minimum brightness; external displays are not changed.
- Closing the red window button hides the interface but leaves the session active.
- Reopening the app restores the control window.
- Disable or quit to restore normal lid-close sleep and the previous brightness.
- At 10% battery, the app automatically restores normal sleep.
- A single session stops after seven days.

Administrator authentication is handled by macOS. The app does not store the password, edit sudoers, install a persistent root helper, create an account, send telemetry, or make network requests.

## Verify and troubleshoot

Treat the app’s green status as the primary user-facing signal. If the state is unclear, inspect the current macOS power-management state without changing it:

```bash
pmset -g custom
```

If the app cannot enable the mode, report the visible macOS error instead of repeatedly requesting authorization. Keep a running MacBook on a hard, ventilated surface and never place it inside a bag.
