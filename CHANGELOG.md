# Changelog

## [0.1.3](https://github.com/lpalokan/bmad-manager/compare/v0.1.2...v0.1.3) (2026-06-09)


### Features

* seed new projects from an existing project's company context ([8b01679](https://github.com/lpalokan/bmad-manager/commit/8b01679d403d759de3ece1658053e9fff1a24046))
* seed new projects from an existing project's company context ([64b932d](https://github.com/lpalokan/bmad-manager/commit/64b932d6a290c878be218190440e731d3fdd429a))

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
