# hardinfo2 on LoongArch64 (loong64)

This fork builds and runs natively on LoongArch64 (Debian/Deepin `loong64`,
glibc 2.38+, GCC 12+). Upstream already carries a basic `loongarch64` port;
this fork fixes the remaining packaging and CPU-report defects found when
building on real hardware (Loongson 3A5000 / Deepin 25).

## Changes in this fork

1. **`CPU Revision` parsing** — `/proc/cpuinfo` reports LoongArch revisions in
   hex (`CPU Revision : 0x11`). Upstream parsed it with `atoi()` into an `int`,
   which always yielded `0`. Changed to a string field (matching the arm port)
   so the real value is shown in the Processor report.
   - `includes/loongarch64/processor-platform.h`
   - `modules/devices/loongarch64/processor.c`

2. **dpkg architecture name** — CMake/``uname`` report `loongarch64`, but Debian
   and Deepin use `loong64` as the package architecture. Without a mapping the
   generated `.deb` is rejected by `dpkg -i` ("package architecture does not
   match"). Mapped `loongarch64` → `loong64`, same as upstream's `x86_64` → `amd64`.

3. **Dependency trimming for loong64** — `sysbench` and `fwupd` are not
   packaged for loong64 in Deepin's repositories. They were hard `Depends`,
   making the `.deb` uninstallable. Removed them from `DEB_REQ`/`RPM_REQ` for
   LoongArch (mirrors the existing riscv handling).

4. **Reproducible build script** — `tools/build-loong64.sh` builds the full
   variant (GTK3 + libsoup3 + Qt5 OpenGL benchmark + Vulkan benchmark) and
   produces an installable `.deb`. Supports a no-root local-dependency mode.

## Build

System dependencies installed (the normal case):

```sh
./tools/build-loong64.sh
```

No root access (downloads `-dev` debs into a local prefix):

```sh
DSH_LOCAL_DEPS=1 ./tools/build-loong64.sh
```

Output: `build-loong64/hardinfo2_*-loong64.deb` with
`Architecture: loong64`.

Install (requires root):

```sh
sudo apt install ./build-loong64/hardinfo2_*-loong64.deb
```

## Verification

- `hardinfo2 -v` → `Release version: Yes (2.3.2) (ARCH_loongarch64)`,
  `OpenGL: QT5`, `Vulkan: X11`.
- `hardinfo2 -r -s -f text` → Processor section shows
  `Model: Loongson-3A5000`, `Revision: 0x11`, correct frequency/features.
- Benchmarks (`FPU FFT`, OpenGL `qgears2`, Vulkan `vkgears`) run natively.

## Known limitations

- CPU feature flags are shown as the raw `Features` string from `/proc/cpuinfo`
  (e.g. `lsx lasx crc32`); there is no flag-meaning translation table like the
  x86/arm ports have. Cosmetic only.
- `sysbench` and `fwupd` related views stay empty until those tools are
  available for `loong64`.
- Team Fortress / remote benchmarking database may not have loong64 reference
  results to compare against.
