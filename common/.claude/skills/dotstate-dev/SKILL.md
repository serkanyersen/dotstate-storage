---
name: DotState Development
description: This skill should be used when working on the DotState project (llm-tui or dotstate repository), "dotstate development", "add a screen to dotstate", "create a dotstate feature", "fix dotstate bug", "dotstate architecture", or any task involving the Rust TUI dotfile manager codebase.
---

# DotState Development Guide

DotState is a terminal-based dotfile manager built with Rust using ratatui for TUI and git2 for Git operations. This skill provides the conventions and patterns required for effective development.

## Project Structure

```
src/
├── main.rs          # Binary entry, CLI parsing, terminal setup
├── app.rs           # Main application loop, screen routing
├── cli.rs           # CLI command definitions
├── lib.rs           # Library root with module exports
├── ui.rs            # State structures and enums
├── styles.rs        # Theme definitions and color system
├── screens/         # Screen controllers (Screen trait implementations)
├── components/      # Reusable UI components (header, footer, help_overlay)
├── services/        # Business logic (git_service, sync_service, profile_service, package_service)
├── utils/           # Utilities (symlink_manager, backup_manager, profile_manifest)
├── widgets/         # Custom ratatui widgets
└── keymap/          # Keyboard configuration with presets
```

## Build and Test Commands

```bash
cargo build              # Build debug
cargo build --release    # Build release
cargo run                # Run TUI
cargo run -- list        # Run CLI command
cargo test               # Run all tests
cargo fmt                # Format code (REQUIRED before commit)
cargo clippy             # Run linter (REQUIRED before commit)
```

## Critical Conventions

### 1. Creating a New Screen

Every screen implements the `Screen` trait from `src/screens/screen_trait.rs`:

```rust
impl Screen for MyScreen {
    fn render(&mut self, frame: &mut Frame, area: Rect, ctx: &RenderContext) -> Result<()>;
    fn handle_event(&mut self, event: Event, ctx: &ScreenContext) -> Result<ScreenAction>;
    fn is_input_focused(&self) -> bool;
    fn on_enter(&mut self, ctx: &ScreenContext) -> Result<()>;
    fn on_exit(&mut self, ctx: &ScreenContext) -> Result<()>;
}
```

**Required steps for new screens:**
1. Create file in `src/screens/my_screen.rs`
2. Implement `Screen` trait
3. Add to `src/screens/mod.rs`: `mod my_screen; pub use my_screen::MyScreen;`
4. Add variant to `src/ui.rs` Screen enum
5. Add routing in `src/app.rs` (initialize, render match arm, event match arm)

### 2. Symlink Management (CRITICAL)

**NEVER use `std::os::unix::fs::symlink` directly.** Always use `SymlinkManager`:

```rust
use crate::utils::SymlinkManager;

let mut symlink_mgr = SymlinkManager::new_with_backup(repo_path.clone(), backup_enabled)?;
symlink_mgr.create_symlink(&source_path, &target_path)?;
symlink_mgr.save_tracking()?;  // REQUIRED after modifications
```

SymlinkManager tracks symlinks in `~/.config/dotstate/symlinks.json` and handles backups.

### 3. Sync Validation (src/utils/sync_validation.rs)

Before adding files/directories to sync, `validate_before_sync()` performs comprehensive checks:

1. **Already synced** - File not already in synced_files
2. **Inside synced directory** - File not inside an already-synced parent directory
3. **Contains synced files** - Directory doesn't contain already-synced files
4. **Git repositories** - No .git folders (direct or nested)
5. **Symlink validation** - For directories, checks for problematic symlinks:
   - Broken symlinks (target doesn't exist)
   - Circular symlinks (would cause infinite recursion/crash)
   - External directory symlinks (points outside, causes scope expansion)
   - Large directory symlinks (>100MB, unexpected disk usage)

**Adding new validation checks:**
```rust
// In validate_before_sync(), add after existing checks:
if full_path.is_dir() {
    match my_new_validation(full_path) {
        Ok(result) if !result.is_safe => {
            return ValidationResult::unsafe_with(format!(
                "Cannot sync directory '{}': reason here",
                normalized
            ));
        }
        Ok(_) => {}
        Err(e) => {
            warn!("Failed to validate: {}", e);
            // Continue or block depending on severity
        }
    }
}
```

**Important:** `copy_dir_all()` in FileManager follows symlinks (dereferences them). It does NOT preserve symlinks - the target content is copied instead. This is why symlink validation happens BEFORE copying.

### 4. Services Layer

Use Services for all business operations, never bypass them:

```rust
use crate::services::{ProfileService, SyncService, PackageService};

ProfileService::activate_profile(repo_path, profile_name, backup_enabled)?;
SyncService::add_file_to_sync(config, full_path, relative_path, backup_enabled)?;
PackageService::get_available_managers();
```

### 5. Text Input Focus Handling

When adding text inputs, guard against global keybindings at the TOP of `handle_event`:

```rust
if self.is_text_input_focused() {
    if let Some(action) = action {
        if !TextInput::is_action_allowed_when_focused(&action) {
            if let KeyCode::Char(c) = key.code {
                if !key.modifiers.intersects(KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SUPER) {
                    self.text_input.insert_char(c);
                    return Ok(ScreenAction::Refresh);
                }
            }
        }
    }
}
```

Without this, keys like 'q' (bound to Quit) will exit the app instead of typing.

### 6. Theme System

Never hardcode colors. Always use the theme system:

```rust
use crate::styles::theme;

let t = theme();
let border_color = t.border;
let text_color = t.text;
let primary = t.primary;
let text_muted = t.text_muted;
let text_emphasis = t.text_emphasis;

// For borders
use crate::utils::{focused_border_style, unfocused_border_style};
let style = if is_focused { focused_border_style() } else { unfocused_border_style() };
```

### 7. Keymap System

Use keymap for all key handling:

```rust
use crate::keymap::{Action, get_action_for_key};

if let Event::Key(key) = event {
    if key.kind != KeyEventKind::Press { return Ok(ScreenAction::None); }

    let action = get_action_for_key(key, &ctx.config.keymap);
    match action {
        Some(Action::Confirm) => { /* Enter */ }
        Some(Action::Cancel) => { /* Esc */ }
        Some(Action::MoveUp) => { /* Up/k */ }
        Some(Action::MoveDown) => { /* Down/j */ }
        _ => {}
    }
}
```

### 8. Error Handling

Use `anyhow` for propagation, `ScreenAction::ShowMessage` for user-facing errors:

```rust
use anyhow::{Context, Result};

let data = fs::read_to_string(path).context("Failed to read config")?;

// For user-facing errors:
return Ok(ScreenAction::ShowMessage {
    title: "Error".to_string(),
    content: format!("Failed to save: {}", e),
});
```

### 9. Async Operations

For long-running operations, use thread + channel pattern:

```rust
use std::sync::mpsc;

// Start async work
let (tx, rx) = mpsc::channel();
std::thread::spawn(move || {
    let result = expensive_operation();
    let _ = tx.send(result);
});

// Store receiver in state
self.state.operation_rx = Some(rx);

// Poll in tick() method (runs every 250ms)
fn tick(&mut self) -> Result<ScreenAction> {
    if let Some(rx) = &self.state.operation_rx {
        if let Ok(result) = rx.try_recv() {
            self.state.operation_rx = None;
            // Handle result
        }
    }
    Ok(ScreenAction::None)
}
```

## Post-Task Checklist

**After completing ANY task:**

1. **Format:** `cargo fmt`
2. **Lint:** `cargo clippy` - fix all warnings
3. **Test:** `cargo test` (if applicable)
4. **Update CHANGELOG.md** under `[Unreleased]`:
   ```markdown
   ### Added/Changed/Fixed
   - **Component**: Brief description
   ```

## Key File Locations

| Purpose | Location |
|---------|----------|
| User config | `~/.config/dotstate/config.toml` |
| Default storage | `~/.config/dotstate/storage/` |
| Symlink tracking | `~/.config/dotstate/symlinks.json` |
| Backups | `~/.dotstate-backups/` |
| Profile manifest | `<repo>/.dotstate-profiles.toml` |

## Common Pitfalls

1. Using raw symlinks instead of SymlinkManager
2. Hardcoding colors instead of using theme()
3. Hardcoding keys instead of keymap system
4. Skipping cargo fmt/clippy before commits
5. Not handling text input focus (global keys interfere)
6. Forgetting to update CHANGELOG for user-visible changes
7. Direct manifest edits without calling ensure_common_symlinks
8. Adding directories without validating symlinks first (can crash on circular symlinks)
9. Assuming copy_dir_all preserves symlinks (it dereferences them)

## Website Documentation

The DotState website is an Astro-based static site with a TUI aesthetic, deployed on Vercel.

### Website Structure

```
website/
├── src/
│   ├── pages/
│   │   └── index.astro      # Main page with all content sections
│   ├── components/          # Reusable Astro components
│   │   ├── CodeBlock.astro      # Code with copy button
│   │   ├── CommandCard.astro    # CLI command documentation
│   │   ├── FeatureCard.astro    # Feature display cards
│   │   ├── InstallWidget.astro  # Tabbed install commands
│   │   ├── Comparison.astro     # Side-by-side comparison
│   │   ├── Tip.astro            # Info/success/warning tips
│   │   ├── Step.astro           # Numbered steps
│   │   └── ...
│   ├── layouts/
│   │   └── Layout.astro     # Base layout with SEO meta tags
│   └── styles/
│       └── global.css       # TUI styling with CSS variables
├── public/
│   └── install.sh           # Install script (served at /install.sh)
├── astro.config.mjs         # Astro configuration
├── vercel.json              # Vercel deployment config
└── package.json
```

### Website Design System

The website uses a TUI-inspired design with:

- **ASCII icons**: `[~]` `[*]` `[+]` `[>]` `[$]` `[#]` `[%]` `[!]` `[&]` instead of emojis
- **Box-drawing lists**: `├─` and `└─` for tree-style lists
- **CSS variables** in `global.css`:
  - `--bg-primary`, `--bg-secondary`, `--bg-tertiary` - backgrounds
  - `--accent-cyan`, `--accent-green` - accent colors
  - `--border-color`, `--border-dim` - borders
  - `--glow-cyan`, `--glow-green` - glow effects
- **Scanline effect**: Subtle CRT-style overlay
- **Terminal chrome**: Headers with box-drawing characters

### Updating Website Content

**CLI Commands** are in the CLI Commands section of `index.astro`:
```astro
<CommandCard
    command="dotstate sync"
    description="Sync with remote..."
    options="<code>-m, --message</code> Custom commit message"
    example="dotstate sync -m 'Update zshrc'"
/>
```

**Features** use FeatureCard components:
```astro
<FeatureCard icon="[@]" title="Profile Management">
    Description here.
</FeatureCard>
```

**Code examples** use CodeBlock:
```astro
<CodeBlock code="cargo install dotstate" />
```

### When to Update the Website

Update the website when:
1. **New CLI commands** are added - add to CLI Commands section
2. **New features** are added - add to Features section
3. **Installation methods change** - update InstallWidget
4. **Configuration options change** - update Configuration section
5. **Version numbers** - header shows version in terminal chrome

### Building the Website

```bash
cd website
npm install          # Install dependencies
npm run build        # Build for production
npm run preview      # Preview locally at localhost:4173
```

Website is auto-deployed to Vercel on push to main.

## Additional Resources

For detailed architecture and data flow, see:
- **`references/architecture.md`** - Services layer, screen lifecycle, state management
