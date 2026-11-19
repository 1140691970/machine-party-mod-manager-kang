# Releasing manager updates

**English** · [简体中文](../../zh-CN/development/releasing.md) · [繁體中文](../../zh-TW/development/releasing.md)

Windows x64 and Apple Silicon Mac clients check `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json` at startup. Players can also see the current version and check manually in Settings. When a newer version exists, the player confirms installation from the prompt. The client verifies the package signature and version. Windows runs the NSIS installer; the Mac replaces the app bundle and restarts the manager. The local catalog stays browsable when the network fails. Design trade-offs are in [ADR-003](../architecture/ADR-003-desktop-updates.md).

## Maintainer release steps

1. Write the same stable version, for example `0.1.2`, in `apps/desktop/src-tauri/Cargo.toml`, `apps/desktop/src-tauri/tauri.conf.json` and the root `package.json`. Run `cargo check` in `apps/desktop/src-tauri` to update the lockfile, record changes in `CHANGELOG.md` and commit to main. `npm test` checks that the three versions match.
2. In GitHub Actions open **Release desktop app**, choose main and run it. The Windows runner produces the production installer and an older acceptance client; the Mac runner produces the Apple Silicon app archive. Both platforms share one stable manifest.
3. Review the commit and build results, then approve production under **Review deployments**. That environment provides the signing key and R2 credentials.
4. The workflow uploads version-specific installers and the manifest, installs the old test client and actually downloads, updates and restarts through the Worker. It checks the running version and local settings, creates the GitHub Release and finally promotes the stable manifest. Installed clients receive the update on their next check.
5. On failure, inspect the failed step first. For transient network errors choose **Re-run failed jobs** to reuse the built installers. To fix the release scripts, start a new run on main with `build_run` set to the original build's run ID. The workflow checks the source and application code (changes to docs, tests, scripts and workflows are allowed) and reuses the original installers. `verify_only` runs only the Windows upgrade acceptance for a staged version. Published installers are pinned per version; replacing content needs a new version number.

If retrying with a historical build returns 403 while creating the Release, a maintainer with push access can run `git push origin <accepted full commit SHA>:refs/tags/v<version>` and rerun the failed job. The workflow checks that the existing tag matches the installer source.

## Hosting and signing

The Worker (`services/update-worker`) reads from `app-releases/` in the private R2 bucket `machine-party-mods`. Each version directory contains setup.exe, MachineParty-aarch64.app.tar.gz and manifest.json. The stable manifest is `stable/latest.json` with caching disabled. Before the first release the stable endpoint returns HTTP 204.

Run **Deploy app update Worker** and approve production when first deploying or changing the Worker. The script binds the project subdomain with the existing Workers permissions. If the zone ID cannot be found automatically, add the production variable `CLOUDFLARE_ZONE_ID`. Deployment uses `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. Releases also use `R2_BUCKET_NAME`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and `TAURI_SIGNING_PRIVATE_KEY`.

For a first install, Windows users download setup.exe from GitHub Releases. Apple Silicon Mac users download MachineParty-aarch64.app.tar.gz, extract it and put the .app in a writable Applications folder. The Mac package is ad hoc signed and not notarised with an Apple Developer ID. Early Mac prototypes lacked the updater and need one manual install of an updater-enabled version. The client embeds the update public key. Keep the matching private key in a protected offline backup; future versions must verify against the public key in installed clients. Tauri update signatures are independent of Windows Authenticode.

The Windows-specific bundle uses MachinePartyModManager as its product directory. Configure repository variables WINDOWS_SIGNING_RUNNER and WINDOWS_SIGNING_THUMBPRINT for a trusted Windows runner with the code-signing certificate and private key already provisioned in its signing store. Restrict that runner to trusted release jobs. The build signs and timestamps the executable and NSIS installer. Stable publication verifies the trusted signature and certificate thumbprint. Preview-only builds may be unsigned when the identity is unavailable.
