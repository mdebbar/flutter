# Pluggable Web Platform Extension Prototype (`flutter_tools_extension_web_prototype`)

This prototype replaces all built-in web-specific code in `flutter_tools` with an out-of-process isolate tool extension built on `package:flutter_tools_core` and `package:flutter_tools_extension`.

---

## 1. What Changed

### A. Built-In Web Code Removed from `flutter_tools`
All hardcoded web implementation files and branches were removed from `packages/flutter_tools`:
- **Deleted directories and modules**:
  - `lib/src/web/**` (`chrome.dart`, `compile.dart`, `compiler_config.dart`, `web_device.dart`, `web_runner.dart`, `web_validator.dart`, `workflow.dart`, `bootstrap.dart`, `memory_fs.dart`, etc.)
  - `lib/src/isolated/resident_web_runner.dart`, `devfs_web.dart`, `web_asset_server.dart`, `web_expression_compiler.dart`, `web_server_utilities.dart`, `release_asset_server.dart`, `proxy_middleware.dart`
  - `lib/src/build_system/targets/web.dart`
  - `lib/src/commands/build_web.dart`
  - `lib/src/drive/web_driver_service.dart`
  - `lib/src/test/flutter_web_platform.dart`, `web_test_compiler.dart`
  - `lib/src/web_template.dart`
- **Removed host special-casing**:
  - `FlutterDeviceManager` no longer instantiates `WebDevices`.
  - `DoctorValidatorsProvider` no longer instantiates `WebValidator` or `WebWorkflow`.
  - `BuildCommand` no longer registers a hardcoded `BuildWebCommand`.
  - `RunCommand`, `Daemon`, and `WidgetPreviewCommand` no longer branch on `webMode` or `WebRunnerFactory`.

### B. Extended Isolate RPC Protocol (`flutter_tools_core` & `flutter_tools_extension`)
To support end-to-end building and running through an extension isolate, the extension protocol was extended with two capability slices:
1. **`BuildService` (`build.*` namespace)**:
   - `build.getTargets` -> returns `List<ExtensionBuildTarget>` (`name`, `description`, `targetPlatform`).
   - `build.build` -> executes a build for `targetName`, `projectRoot`, `mainPath`, `buildMode`, and `options`, returning an `ExtensionBuildResult` (`success`, `outputDirectory`, `errorMessage`).
2. **`DeviceService` App Lifecycle (`device.*` namespace)**:
   - `device.startApp` -> builds/launches the app on `deviceId` and returns `ExtensionLaunchResult` (`succeeded`, `vmServiceUri`, `appUrl`, `errorMessage`).
   - `device.reloadApp` -> triggers hot reload or hot restart (`fullRestart`) on `deviceId` and returns `ExtensionReloadResult` (`succeeded`, `message`).
   - `device.stopApp` -> stops the active session and cleans up device resources.

### C. Host-Side Dynamic Dispatch (`packages/flutter_tools/lib/src/experimental/`)
- **`ExtensionBuildManager` & `ExtensionBuildSubCommand`**: Queries active `BuildService` extensions during `BuildCommand.initializeDynamicOptions()` and dynamically registers `flutter build <target>` subcommands (including `flutter build web`).
- **`ExtensionResidentRunner` & `ExtensionBackedDevice`**: Implements a generic `ResidentRunner` that delegates `run()`, `restart()` (`r` / `R`), and `cleanupAtFinish()` (`q` / SIGINT) over JSON-RPC to `DeviceService`.
- **`toolExtensionsFeature`**: Enabled by default across channels so extensions load automatically on startup.

### D. New Web Extension Package (`packages/flutter_tools/packages/flutter_tools_extension_web_prototype/`)
Registered via `webExtensionEntryPoint` in `executable.dart`, running in a dedicated worker isolate and providing:
- **`WebExtensionDiagnostics`**: Locates Chrome/Chromium (`CHROME_EXECUTABLE` or standard OS paths), queries `--version`, and reports status to `flutter doctor`.
- **`WebConfigurationExtension`**: Contributes `--[no-]enable-web` and `--web-browser-flag` to `flutter config`.
- **`WebTemplateService`**: Contributes the `web-app` project template (`web/index.html`, `web/manifest.json`, `lib/main.dart`, `pubspec.yaml`) to `flutter create`.
- **`WebBuildService`**: Registers the `web` target (`flutter build web`), copies `web/` assets, interpolates `{{flutter_js}}` and `{{flutter_build_config}}` in `index.html` / `flutter_bootstrap.js`, and compiles `main.dart.js`.
- **`WebDeviceService`**: Exposes `chrome` (`Chrome (web)`) and `web-server` (`Web Server (web)`), serves `build/web` over a local `shelf` HTTP server, launches Chrome with `--remote-debugging-port`, and reloads the active tab via Chrome DevTools Protocol (`webkit_inspection_protocol`) on hot reload/restart.

---

## 2. How to Use It

If running via the `flutter` wrapper script, first delete any cached `flutter_tools` snapshot so it rebuilds from this branch (or run directly via `dart packages/flutter_tools/bin/flutter_tools.dart`):

```bash
rm -f bin/cache/flutter_tools.stamp bin/cache/flutter_tools.snapshot
```

### Check Web Toolchain Diagnostics (`flutter doctor`)
```bash
dart packages/flutter_tools/bin/flutter_tools.dart doctor -v
```
Output includes the validator contributed by `WebExtensionDiagnostics`:
```text
[✓] Chrome - develop for the web [Google Chrome 155.0.8059.39]
    • Chrome at /usr/bin/google-chrome
    • Google Chrome 155.0.8059.39
```

### Inspect Web Configuration Flags (`flutter config`)
```bash
dart packages/flutter_tools/bin/flutter_tools.dart config --help
```
Output includes options contributed by `WebConfigurationExtension`:
```text
--[no-]enable-web        Enable or disable Flutter for web. (defaults to on)
--web-browser-flag       Additional flags to pass to Chrome when launching a web app.
```

### List Web Devices (`flutter devices`)
```bash
dart packages/flutter_tools/bin/flutter_tools.dart devices
```
Output includes devices contributed by `WebDeviceService`:
```text
Chrome (web)     • chrome     • web-javascript • Google Chrome 155.0.8059.39
Web Server (web) • web-server • web-javascript • Flutter Tools
```

### Scaffold a New Web Project (`flutter create`)
```bash
dart packages/flutter_tools/bin/flutter_tools.dart create --template=web-app /tmp/my_web_app
```

### Build a Web Bundle (`flutter build web`)
```bash
cd /tmp/my_web_app
dart /path/to/flutter/packages/flutter_tools/bin/flutter_tools.dart build web
```
Produces `build/web/{index.html,flutter_bootstrap.js,main.dart.js,flutter.js,manifest.json,favicon.png,assets/}` via `WebBuildService`.

### Run on `web-server` or `chrome` (`flutter run`)
```bash
# Run on the headless/local HTTP web server:
dart /path/to/flutter/packages/flutter_tools/bin/flutter_tools.dart run -d web-server

# Or launch Chrome connected to the local server:
dart /path/to/flutter/packages/flutter_tools/bin/flutter_tools.dart run -d chrome
```
While running, press `r` / `R` to trigger `WebDeviceService.reloadApp` (rebuilding `build/web` and issuing `Page.reload` over the Chrome DevTools Protocol), or `q` to invoke `WebDeviceService.stopApp`.

### Run the Unit & Protocol Tests
```bash
cd packages/flutter_tools
../../bin/cache/dart-sdk/bin/dart test \
  packages/flutter_tools_core/test \
  packages/flutter_tools_extension_web_prototype/test \
  test/general.shard/extension_protocol
```

---

## 3. Benefits of This Change

1. **Eliminates Platform Coupling in `flutter_tools`**:
   The host CLI no longer contains web-specific imports (`src/web/*`), compiler flags, asset server implementations, or `if (webMode)` branches across `run`, `build`, `doctor`, `daemon`, and `device_manager`. Every platform interaction flows through uniform `ExtensionManager` services.
2. **Process & Dependency Isolation**:
   Web tooling runs inside a separate worker isolate communicating over JSON-RPC 2.0 (`IsolateChannel`). Heavy web-only dependencies (`shelf`, `webkit_inspection_protocol`, `dwds`, HTML/JS template generators) and runtime state are isolated from the core `flutter_tools` host.
3. **Out-of-Tree & Independent Versioning Path**:
   Because the web implementation consumes only `package:flutter_tools_core` and `package:flutter_tools_extension` (with zero imports back into `package:flutter_tools`), it can be moved out of the `flutter/flutter` monorepo and published/updated on its own schedule.
4. **Proves the Pluggable Platform Architecture End-to-End**:
   Moving a complex first-party target platform (requiring custom JS compilation, an HTTP server, browser process management, and CDP page reload) onto the same extension API used by custom embedders validates that the pluggable platform contract is sufficient for full-featured platforms.
