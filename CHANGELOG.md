# Changelog

## [0.1.3](https://github.com/lpalokan/bmad-manager/compare/v0.1.2...v0.1.3) (2026-06-14)


### Features

* add Codex to the enabled coding-agent harnesses ([11ab3fc](https://github.com/lpalokan/bmad-manager/commit/11ab3fc642d6cf7fcfc97c9538b0d00f5e1ac74a))
* add Open Folder button to the Tauri project rows ([0bd39f6](https://github.com/lpalokan/bmad-manager/commit/0bd39f6271938651f11e7feafb02ffb5f408bb2d))
* alphabetise project-row agent buttons (Tauri) ([f4efc5d](https://github.com/lpalokan/bmad-manager/commit/f4efc5d485957b32228a1f06be4ac51684a32235))
* App-vs-CLI launch for Claude & Codex (consolidates Windows+Codex port) ([a82f221](https://github.com/lpalokan/bmad-manager/commit/a82f221b27516ef9c13791ebb0c37fa31fc90f4b))
* choose CLI or desktop app when launching Claude and Codex ([14780aa](https://github.com/lpalokan/bmad-manager/commit/14780aa34ce1245cb509cf97e4949e20b160aefb)), closes [#41](https://github.com/lpalokan/bmad-manager/issues/41)
* global skill sync into Claude Code and Codex (Mac + Windows) ([c8a2da0](https://github.com/lpalokan/bmad-manager/commit/c8a2da0b9ff8f21d53cf46a3dfeb7126986cb66a))
* global skill sync into Claude Code and Codex (Swift/macOS) ([34894ad](https://github.com/lpalokan/bmad-manager/commit/34894adcceea02b145850c469200edd1248dd9f6))
* global skill sync into Claude Code and Codex (Tauri/Windows) ([4258dc5](https://github.com/lpalokan/bmad-manager/commit/4258dc5d5436800b4e108da9b06007bf79d8fb81))
* open the project folder when launching an agent's desktop app ([f9093bc](https://github.com/lpalokan/bmad-manager/commit/f9093bc25e11974a186564dacbc9ebe8de4001ad))
* per-agent launch label and alphabetised project-row actions (Swift) ([92de1b9](https://github.com/lpalokan/bmad-manager/commit/92de1b941e7bc73adde202ed1b6f2d0309da6729))
* seed new projects from an existing project's company context ([8b01679](https://github.com/lpalokan/bmad-manager/commit/8b01679d403d759de3ece1658053e9fff1a24046))
* seed new projects from an existing project's company context ([64b932d](https://github.com/lpalokan/bmad-manager/commit/64b932d6a290c878be218190440e731d3fdd429a))
* seed new projects from an existing project's company context (Windows port) ([e136181](https://github.com/lpalokan/bmad-manager/commit/e136181b28fb654a513d16d853de5a0884bc2c10))
* write a Codex AGENTS.md on project creation to route BMad menu codes ([9aed4b2](https://github.com/lpalokan/bmad-manager/commit/9aed4b21d7a16327d00f5025092690c148f0f4fe))


### Bug Fixes

* clarify what App launch opens for Claude vs Codex in Settings ([76ee533](https://github.com/lpalokan/bmad-manager/commit/76ee533d6965850ef63c0538b8bfeff11613e266))
* link synced skills as direct children so Claude Code/Codex find them ([3dd9699](https://github.com/lpalokan/bmad-manager/commit/3dd9699f8016173f32370fd3c30b82a94de4c4aa))
* make bmad-method --custom-source accept Windows module paths ([9910583](https://github.com/lpalokan/bmad-manager/commit/9910583ecba2e930af8f2051688c0e1ce7536c5d))
* make Settings 'Reset to defaults' actually restore defaults ([0fea0eb](https://github.com/lpalokan/bmad-manager/commit/0fea0eb00713232fe46d13052d55eb158d2c95e6))
* pass cmd.exe the init command verbatim so quoted paths survive ([779171b](https://github.com/lpalokan/bmad-manager/commit/779171b9a639a1c42761489e0dc63e804214884e))
* refresh the project list without an app restart ([3c32284](https://github.com/lpalokan/bmad-manager/commit/3c322849a7661b36808e70526fec12aad6743e8e))
* return owned PathBuf from settings_dir to satisfy borrow checker ([c2de1b6](https://github.com/lpalokan/bmad-manager/commit/c2de1b69c094e52a898f77c89599698708e76ecc))
* strip ANSI/spinner escape codes from install output ([4f2fb3a](https://github.com/lpalokan/bmad-manager/commit/4f2fb3a8209273513d3061f344cce862d6d29597))

## [0.1.2](https://github.com/lpalokan/bmad-manager/compare/v0.1.1...v0.1.2) (2026-05-23)


### Features

* add Pi coding agent and PATH detection for agent commands ([99cf40f](https://github.com/lpalokan/bmad-manager/commit/99cf40f34145d0f26b762b1b0b657c3331363238))
* add Pi coding agent and PATH detection for agent commands ([a3085e7](https://github.com/lpalokan/bmad-manager/commit/a3085e72ab79403512d71c011f6a9c87db6cd149))
* back-port Pi agent and PATH detection to the Swift macOS app ([a31b640](https://github.com/lpalokan/bmad-manager/commit/a31b640e84ac558ad81ccb90a81b1f199bc6aeff))


### Bug Fixes

* detect curl-installed quarantined binaries like opencode ([c0b89b4](https://github.com/lpalokan/bmad-manager/commit/c0b89b4423ec0e702dfbb07e80c67e598bf4442c))
* honour Terminal-vs-iTerm2 choice on the very first click ([0cb694f](https://github.com/lpalokan/bmad-manager/commit/0cb694fde5b4f91dacf6d8fc7aba5cfa35bfebc9))
* kill the App.init capture dance behind multiple drift bugs ([c281fbd](https://github.com/lpalokan/bmad-manager/commit/c281fbd97bdfdfdcb34b513c9308ef4c5cd19a81))
* pi in default --tools list, satisfy fmt+clippy on Windows CI ([b3bd735](https://github.com/lpalokan/bmad-manager/commit/b3bd735abec25feec6937763e4a7c74cb368bcaf))
* scroll long Settings dialog and detect via login-shell PATH ([f0e02ca](https://github.com/lpalokan/bmad-manager/commit/f0e02caac12ad707204e607efbed7abe54ad696d))

## [0.1.1](https://github.com/lpalokan/bmad-manager/compare/v0.1.0...v0.1.1) (2026-05-23)


### Bug Fixes

* actually execute shell command in testPlaceholderSubstitution ([74d07d2](https://github.com/lpalokan/bmad-manager/commit/74d07d2368d0edaae8c50773f1ebae8b0c6e3192))
* add [@preconcurrency](https://github.com/preconcurrency) to XCTest import to suppress isolation mismatch warning ([69c7c72](https://github.com/lpalokan/bmad-manager/commit/69c7c7216c237ffcc04c4974b9b70e64d5431f3b))
* drain pipe data in terminationHandler to prevent race condition ([2a9951e](https://github.com/lpalokan/bmad-manager/commit/2a9951e2861fc1767878b15db501b63170bfa7ac))
* resolve MainActor concurrency errors and zip fixture in ProjectCoordinatorTests ([59fd675](https://github.com/lpalokan/bmad-manager/commit/59fd6755699fbdf0a20842c2d1b7757de4e42ba9))
