# DotState Architecture Reference

## Services Layer Architecture

```
┌─────────────────────────────────────────────────┐
│                   UI Layer                      │
│  (App, Screens, Components)                     │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────┐
│               Services Layer                       │
│  ┌─────────────┐ ┌───────────────┐ ┌──────────────┐│
│  │ SyncService │ │ProfileService │ │PackageService││
│  └─────────────┘ └───────────────┘ └──────────────┘│
│  ┌───────────────┐                                 │
│  │ GitService    │                                 │
│  └───────────────┘                                 │
└─────────────────────┬──────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────┐
│             Infrastructure Layer                 │
│  (SymlinkManager, BackupManager, Config, etc.)   │
└──────────────────────────────────────────────────┘
```

## Main Application Flow

### Event Loop (src/app.rs)

```rust
loop {
    // 1. Render current screen
    terminal.draw(|frame| {
        current_screen.render(frame, area, &render_ctx);
    })?;

    // 2. Poll for events
    if crossterm::event::poll(Duration::from_millis(250))? {
        let event = crossterm::event::read()?;

        // 3. Dispatch to current screen
        let action = current_screen.handle_event(event, &screen_ctx)?;

        // 4. Process ScreenAction
        match action {
            ScreenAction::None => {}
            ScreenAction::Navigate(screen) => { /* switch screens */ }
            ScreenAction::ShowMessage { title, content } => { /* show dialog */ }
            ScreenAction::Quit => break,
            ScreenAction::Refresh => { /* just redraw */ }
        }
    }

    // 5. Call tick for background work
    current_screen.tick()?;
}
```

### Screen Lifecycle

1. **on_enter()** - Called when navigating TO the screen. Initialize state, load data.
2. **render()** - Called every frame. Draw UI using ratatui widgets.
3. **handle_event()** - Called for keyboard/mouse events. Return ScreenAction.
4. **tick()** - Called every 250ms. Poll async operations, update animations.
5. **on_exit()** - Called when navigating AWAY. Cleanup, save state.

## Context Objects

### RenderContext (read-only, for rendering)

```rust
pub struct RenderContext<'a> {
    pub config: &'a Config,
    pub git_status: Option<&'a GitStatus>,
}
```

### ScreenContext (read-only, for event handling)

```rust
pub struct ScreenContext<'a> {
    pub config: &'a Config,
    pub git_manager: Option<&'a GitManager>,
}
```

## State Management

### UI State (src/ui.rs)

Contains all mutable state for the application:

```rust
pub struct ManagePackagesState {
    // List state
    pub packages: Vec<Package>,
    pub list_state: ListState,
    pub selected_index: usize,

    // Popup state
    pub show_add_popup: bool,
    pub popup_fields: PopupFields,

    // Async operation state
    pub loading: bool,
    pub operation_rx: Option<Receiver<Result>>,

    // Cache
    pub status_cache: HashMap<String, PackageStatus>,
}
```

### Screen State Pattern

Each screen typically has:
1. **Display state** - What's shown (list items, selected index)
2. **Popup/dialog state** - Modal UI state
3. **Async state** - Receivers for background operations
4. **Cache state** - Cached data to avoid re-fetching

## Services Reference

### GitService (src/services/git_service.rs)

Handles all Git operations via git2:

```rust
GitService::sync_with_remote(config, token)  // Full sync: commit, pull --rebase, push
GitService::get_status(repo_path)            // Get repo status
GitService::commit(repo_path, message)       // Create commit
```

### SyncService (src/services/sync_service.rs)

Manages file synchronization:

```rust
SyncService::add_file_to_sync(config, full_path, relative_path, backup_enabled)
SyncService::remove_file_from_sync(config, file_path)
SyncService::get_synced_files(repo_path, profile)
```

### Sync Validation (src/utils/sync_validation.rs)

Pre-sync validation to prevent data loss and crashes:

```rust
use crate::utils::sync_validation::{validate_before_sync, ValidationResult};

let result = validate_before_sync(relative_path, full_path, &synced_files, repo_path);
if !result.is_safe {
    return Err(anyhow::anyhow!(result.error_message.unwrap()));
}
```

**Validation checks performed:**

| Check | Function | Purpose |
|-------|----------|---------|
| Already synced | `synced_files.contains()` | Prevent duplicates |
| Inside synced dir | `is_file_inside_synced_directory()` | Prevent nested conflicts |
| Contains synced | `directory_contains_synced_files()` | Prevent directory/file conflicts |
| Git repo | `contains_git_repo()` | No .git in parents |
| Nested git | `contains_nested_git_repo()` | No .git in children |
| Symlinks | `validate_directory_symlinks()` | Broken, circular, external, large |

**Symlink validation types:**

```rust
pub enum SymlinkIssue {
    Broken { symlink_path, target_path },      // Target doesn't exist
    Circular { symlink_path, target_path },    // Would cause infinite recursion
    External { symlink_path, target_path },    // Points outside directory
    LargeDirectory { symlink_path, target_path, size_bytes }, // >100MB
}
```

### ProfileService (src/services/profile_service.rs)

Manages profiles:

```rust
ProfileService::activate_profile(repo_path, name, backup_enabled)
ProfileService::switch_profile(repo_path, from, to, backup_enabled)
ProfileService::create_profile(repo_path, name, description, copy_from)
ProfileService::delete_profile(repo_path, name)
ProfileService::ensure_common_symlinks(repo_path, backup_enabled)
```

### PackageService (src/services/package_service.rs)

Manages packages:

```rust
PackageService::get_available_managers()     // Detect installed package managers
PackageService::check_package(package)       // Check if package installed
PackageService::install_package(package)     // Install via package manager
```

## Profile Manifest (src/utils/profile_manifest.rs)

The manifest file `.dotstate-profiles.toml` stores profile definitions:

```toml
[[profiles]]
name = "work"
description = "Work configuration"
synced_files = ["config/git/config", "config/nvim/init.lua"]

[[profiles]]
name = "home"
description = "Home configuration"
synced_files = ["config/git/config"]

[common]
synced_files = ["zshrc", "bashrc"]  # Shared across all profiles

[packages]
packages = [
    { name = "ripgrep", binary = "rg", manager = "brew" },
    { name = "fd", binary = "fd", manager = "brew" },
]
```

## Package Discovery (src/utils/package_discovery.rs)

Discovers installed packages from system package managers:

```rust
// Available sources
enum DiscoverySource {
    Homebrew, Pacman, Apt, Dnf, Yum, Snap,
    Cargo, Npm, Pip, Pip3, Gem
}

// Async discovery
let rx = PackageDiscoveryService::discover_source_async(source);

// Poll for results
match rx.try_recv() {
    Ok(DiscoveryStatus::Completed(packages)) => { /* handle */ }
    Ok(DiscoveryStatus::Failed(error)) => { /* handle */ }
    Err(TryRecvError::Empty) => { /* still loading */ }
    Err(TryRecvError::Disconnected) => { /* channel closed */ }
}
```

## Git Operations (src/git.rs)

Low-level Git operations using git2:

```rust
impl GitManager {
    pub fn pull_with_rebase(&self, remote, branch, token) -> Result<usize>
    pub fn push(&self, remote, branch, token) -> Result<()>
    pub fn commit_all(&self, message) -> Result<Oid>
    pub fn fetch(&self, remote, branch, token) -> Result<()>
}
```

### Pull with Rebase Flow

1. Fetch from remote
2. Check if FETCH_HEAD exists
3. Compare local HEAD with remote:
   - Same commit → already up to date
   - Local at merge base → fast-forward
   - Local ahead → perform rebase
4. After rebase:
   - Update branch reference to new HEAD
   - Set HEAD to point to branch (not detached)
   - Checkout HEAD to update working directory

## Component Patterns

### Standard Screen Layout

```rust
use crate::utils::{create_standard_layout, create_split_layout};

fn render(&mut self, frame: &mut Frame, area: Rect, ctx: &RenderContext) -> Result<()> {
    let layout = create_standard_layout(area);  // header, content, footer

    Header::new("Screen Title").render(frame, layout.header);

    // Render content in layout.content

    Footer::new(&footer_items).render(frame, layout.footer, ctx.config);

    Ok(())
}
```

### Popup Pattern

```rust
// Render popup over main content
if self.state.show_popup {
    let popup_area = centered_rect(60, 50, area);
    frame.render_widget(Clear, popup_area);  // Clear background

    let block = Block::default()
        .title("Popup Title")
        .borders(Borders::ALL)
        .border_style(focused_border_style());

    frame.render_widget(block, popup_area);
    // Render popup content inside
}
```

### List with Selection

```rust
let items: Vec<ListItem> = self.state.items.iter()
    .enumerate()
    .map(|(i, item)| {
        let style = if i == self.state.selected_index {
            Style::default().bg(theme().highlight_bg)
        } else {
            Style::default()
        };
        ListItem::new(item.name.clone()).style(style)
    })
    .collect();

let list = List::new(items)
    .block(Block::default().borders(Borders::ALL));

frame.render_stateful_widget(list, area, &mut self.state.list_state);
```

## FileManager (src/file_manager.rs)

Handles file operations for syncing:

```rust
let fm = FileManager::new()?;
fm.copy_to_repo(&source, &dest)?;  // Copies file or directory
fm.is_symlink(&path);               // Check if path is symlink
fm.resolve_symlink(&path)?;         // Follow symlink chain to target
```

**Important: `copy_dir_all()` behavior with symlinks:**

- Uses `path.is_dir()` which **follows symlinks** (not `symlink_metadata`)
- Symlinks to files: `fs::copy()` dereferences and copies file content
- Symlinks to directories: Recursively copies the **target directory's contents**
- **Does NOT preserve symlinks** - they become regular files/directories
- Circular symlinks cause **stack overflow/crash** (why validation exists)

This is why `validate_directory_symlinks()` must run BEFORE `copy_dir_all()`.

## Dependencies

| Crate | Purpose |
|-------|---------|
| ratatui | TUI framework |
| crossterm | Terminal backend |
| git2 | Git operations (with vendored-openssl) |
| toml, serde | Configuration parsing |
| reqwest, tokio | HTTP/async for GitHub API |
| clap | CLI argument parsing |
| syntect | Syntax highlighting |
| chrono | Date/time handling |
| tracing | Logging |
| anyhow | Error handling |
