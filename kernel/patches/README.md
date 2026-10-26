# Kernel patches

`*.patch` files here are applied in name order on top of the pinned
sc7280-mainline tag before every kernel build. Number them (`0001-...`) and
bump `KERNEL_PKG_RELEASE` in `config.env` when you add or change one.

Planned work is described in `docs/hardware-findings.md`.
