# [Omaspeedmeter](https://omarchyplugins.com/plugin.html?id=mt-shihab26.omaspeedmeter)

[![Omarchy 4.0+](https://img.shields.io/badge/Omarchy-4.0%2B-c6aa75?style=flat-square)](https://omarchy.org/manual/shell-plugins/)
[![Validate](https://img.shields.io/github/actions/workflow/status/mt-shihab26/omaspeedmeter/validate.yml?branch=main&style=flat-square&label=validate)](https://github.com/mt-shihab26/omaspeedmeter/actions/workflows/validate.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-6aa6b2?style=flat-square)](LICENSE)

[Omarchy](https://omarchy.org/) bar widget showing CPU, memory, swap, network, temperature, GPU, and process count stats.

Click the widget in the bar to open a settings popup where you can toggle
metrics, reorder segments, split network into up/down segments, switch icons
for word labels, move the widget between bar sections, and change the
refresh interval, GPU vendor, temperature source, and network interface —
all without editing config files by hand. Right-click the widget to open a
system monitor (`btop` by default, or `htop`).

<table>
<tr>
<td><img src="preview.png" width="100%" alt="Omaspeedmeter bar widget preview"></td>
<td><video src="https://github.com/user-attachments/assets/61c83f7d-98f9-4b38-8a60-5e8d97d5fa49" width="100%" controls></video></td>
</tr>
</table>

## Installation

```bash
omarchy plugin add https://github.com/shafayetejaman/mt-shihab26.omaspeedmeter.git --enable
```

To remove it:

```bash
omarchy plugin remove mt-shihab26.omaspeedmeter
```

See the [Omarchy plugin manual](https://omarchy.org/manual/shell-plugins/) for
more on `omarchy plugin` commands.

## Metrics

| Metric  | Source                                                                                                                                              | Notes                                                                    |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Network | [`/sys/class/net/<iface>/statistics/*_bytes`](https://docs.kernel.org/networking/statistics.html)                                                   | Combined or split into download/upload                                   |
| CPU     | [`/proc/stat`](https://man7.org/linux/man-pages/man5/proc_stat.5.html)                                                                              | Usage % since the previous poll                                          |
| Temp    | [`/sys/class/thermal/thermal_zone*/temp`](https://docs.kernel.org/driver-api/thermal/sysfs-api.html)                                                | Prefers the CPU package/core sensor                                      |
| Memory  | [`/proc/meminfo`](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)                                                                        | `(MemTotal - MemAvailable) / MemTotal`                                   |
| Swap    | [`/proc/meminfo`](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)                                                                        | `(SwapTotal - SwapFree) / SwapTotal`; shows `…` if no swap is configured |
| GPU     | [`nvidia-smi`](https://docs.nvidia.com/deploy/nvidia-smi/index.html), sysfs, or [`intel_gpu_top`](https://man.archlinux.org/man/intel_gpu_top.1.en) | Vendor auto-detected                                                     |
| Procs   | [`/proc/[0-9]*`](https://man7.org/linux/man-pages/man5/proc.5.html)                                                                                 | Count of running process directories                                     |

Each metric shows as a [Nerd Font](https://www.nerdfonts.com/) glyph icon by
default, from the glyph set Omarchy already ships for the bar, so they render
consistently with the built-in widgets. Enable **word labels** in the
settings popup to show `CPU`, `MEM`, etc. instead.

CPU and network are rate-based and need two polls to produce a real number,
so they show `…` for the first tick after the widget loads or after the
refresh interval changes.

## Settings

All settings are toggled/edited from the bar widget's click popup, and are
persisted via [`omarchy bar set`](https://omarchy.org/manual/the-top-bar/).

| Setting         | Default             | Description                                                                    |
| --------------- | ------------------- | ------------------------------------------------------------------------------ |
| `net`           | `true`              | Show network speed                                                             |
| `cpu`           | `true`              | Show CPU usage %                                                               |
| `temp`          | `false`             | Show CPU temperature                                                           |
| `mem`           | `true`              | Show memory usage %                                                            |
| `swap`          | `false`             | Show swap usage %                                                              |
| `gpu`           | `false`             | Show GPU usage %                                                               |
| `procs`         | `false`             | Show running process count                                                     |
| `netSplit`      | `false`             | Show download/upload as two separate segments                                  |
| `labels`        | `false`             | Show word labels (`CPU`, `MEM`, ...) instead of icons                          |
| `interval`      | `2`                 | Refresh interval, in seconds                                                   |
| `gap`           | `17`                | Spacing between segments, in pixels (matches Omarchy's own bar widget spacing) |
| `gpuVendor`     | `auto`              | `auto`, `nvidia`, `amd`, `intel`, or `none`                                    |
| `netIface`      | `auto`              | `auto`, or a specific network interface name                                   |
| `tempZone`      | `auto`              | `auto`, or a specific `/sys/class/thermal/thermal_zone*/temp` path             |
| `systemMonitor` | `btop`              | `btop` or `htop`; opened by right-clicking the widget                          |
| `order`         | _(insertion order)_ | Segment display order; set with the ▲/▼ buttons in the popup's METRICS list    |

`auto` for GPU vendor and temperature zone probes the system on each poll;
pinning a specific value skips detection and avoids picking the wrong sensor
on machines with multiple thermal zones or GPUs. The network interface and
temperature zone dropdowns are populated live from
[`/sys/class/net`](https://docs.kernel.org/networking/statistics.html) and
[`/sys/class/thermal`](https://docs.kernel.org/driver-api/thermal/sysfs-api.html)
when the popup opens.

The bar position dropdown (left/center/right) reads and writes the widget's
placement via [`omarchy-shell`](https://omarchy.org/manual/omarchy-cli/)/
[`omarchy bar move`](https://omarchy.org/manual/the-top-bar/), independent of
the `defaultSection` set on first install.

Each row in the popup's METRICS list has ▲/▼ buttons to move that metric up
or down; the bar segments re-render in the new order immediately, and it
persists the same way as every other setting. The ↺ button next to the
popup title resets every setting in the table above back to its default,
including the segment order.

### Config file

Every setting above (plus the bar position) is also mirrored to a
hand-editable JSON file at `~/.config/omaspeedmeter/config.json`
(`$XDG_CONFIG_HOME/omaspeedmeter/config.json` if set), kept in sync with the
popup in both directions:

- Changing a setting in the popup updates the config file.
- Editing the config file (with the widget running) applies the change live —
  through the same path a popup click would use, so it also updates via
  `omarchy bar set`/`omarchy bar move` and stays consistent with the popup.

```json
{
    "cpu": true,
    "mem": true,
    "swap": false,
    "net": true,
    "temp": false,
    "gpu": false,
    "procs": false,
    "labels": false,
    "netSplit": false,
    "interval": 2,
    "gap": 17,
    "gpuVendor": "auto",
    "tempZone": "auto",
    "netIface": "auto",
    "systemMonitor": "btop",
    "order": ["net", "cpu", "temp", "mem", "swap", "gpu", "procs"],
    "section": "right"
}
```

`order` and `section` accept the same values as the `order` setting and bar
position dropdown above; unknown keys are ignored and missing keys keep
their current value.

## How it works

Each metric is collected by a small standalone bash script in [`bin/`](bin),
run on a timer by [`BarWidget.qml`](BarWidget.qml) and merged into a single
stats object:

- [`omaspeedmeter-cpu`](bin/omaspeedmeter-cpu) — reads
  [`/proc/stat`](https://man7.org/linux/man-pages/man5/proc_stat.5.html),
  diffs against a cached previous sample in
  [`$XDG_CACHE_HOME`](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)`/omaspeedmeter/cpu`
  to compute usage %.
- [`omaspeedmeter-mem`](bin/omaspeedmeter-mem) — reads
  [`/proc/meminfo`](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)
  directly (no state needed).
- [`omaspeedmeter-swap`](bin/omaspeedmeter-swap) — reads
  [`/proc/meminfo`](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)
  directly; emits `null` when no swap is configured.
- [`omaspeedmeter-net`](bin/omaspeedmeter-net) — reads interface byte
  counters from sysfs, diffs against `$XDG_CACHE_HOME/omaspeedmeter/net` to
  compute throughput.
- [`omaspeedmeter-temp`](bin/omaspeedmeter-temp) — reads a thermal zone from
  sysfs, auto-preferring a zone whose type matches a known CPU sensor
  (`coretemp`, `k10temp`, etc.).
- [`omaspeedmeter-gpu`](bin/omaspeedmeter-gpu) — detects the GPU vendor and
  shells out to [`nvidia-smi`](https://docs.nvidia.com/deploy/nvidia-smi/index.html),
  AMD's `gpu_busy_percent` sysfs file, or
  [`intel_gpu_top`](https://man.archlinux.org/man/intel_gpu_top.1.en).
- [`omaspeedmeter-procs`](bin/omaspeedmeter-procs) — counts
  [`/proc/[0-9]*`](https://man7.org/linux/man-pages/man5/proc.5.html)
  directories.

Each script only runs when its metric is enabled, and only prints a single
line of JSON (e.g. `{"cpu":42}`), which [`Model.js`](Model.js) parses and
formats into the bar segments. `Model.js` holds all the pure logic (settings
resolution, formatting, segment building) separately from the QML so it can
be reasoned about — and unit tested — without a
[Quickshell](https://quickshell.org/) runtime.

Right-clicking the widget opens the configured `systemMonitor` (`btop` by
default, or `htop`) via
[`omarchy-launch-or-focus-tui`](https://omarchy.org/manual/omarchy-cli/),
focusing an existing window for it instead of spawning a duplicate if one is
already open.

`~/.config/omaspeedmeter/config.json` is watched with a Quickshell
[`FileView`](https://quickshell.org/), the same mechanism the Omarchy shell
itself uses to hot-reload `~/.config/omarchy/shell.json`. A change to either
side — the popup or the file — is serialized through the same
`setSetting`/`setSection` calls, so both stay consistent with each other and
with `omarchy bar set`/`omarchy bar move`.

## Requirements

- Linux with [`/proc`](https://man7.org/linux/man-pages/man5/proc.5.html) and
  [`/sys`](https://docs.kernel.org/filesystems/sysfs.html) available
  (standard on any distro).
- [`awk`](https://www.gnu.org/software/gawk/manual/gawk.html),
  [`bash`](https://www.gnu.org/software/bash/manual/bash.html),
  [`ip`](https://man7.org/linux/man-pages/man8/ip.8.html) — present on
  virtually every system.
- GPU stats additionally require, depending on vendor:
    - NVIDIA: [`nvidia-smi`](https://docs.nvidia.com/deploy/nvidia-smi/index.html)
    - AMD: no extra tooling (reads sysfs directly)
    - Intel: [`intel_gpu_top`](https://man.archlinux.org/man/intel_gpu_top.1.en)
      and [`jq`](https://jqlang.github.io/jq/manual/)
- Right-click requires whichever `systemMonitor` is configured
  ([`btop`](https://github.com/aristocratos/btop) or
  [`htop`](https://htop.dev/)) to be installed.

If a required tool is missing, that metric's script emits `null` and the
segment is skipped rather than erroring.

## Project structure

```
.
├── .github/workflows/validate.yml  # CI: lint/format check on push and PR
├── CHANGELOG.md                    # notable changes per version
├── bin/                            # standalone stat-collector scripts, one per metric
│   ├── omaspeedmeter-cpu
│   ├── omaspeedmeter-gpu
│   ├── omaspeedmeter-mem
│   ├── omaspeedmeter-net
│   ├── omaspeedmeter-procs
│   ├── omaspeedmeter-swap
│   └── omaspeedmeter-temp
├── BarWidget.qml                   # bar segment UI, settings popup, polling timer
├── Model.js                        # pure logic: settings resolution, formatting, segments
├── manifest.json                   # Omarchy plugin manifest (id, defaults, settings schema)
├── format.sh                       # qmlformat + Prettier, run before committing
├── link.sh                         # symlinks the repo into ~/.config/omarchy/plugins
└── preview.png                     # screenshot used in this README
```

## Development

```bash
git checkout dev
```

Development happens on `dev`. Run `./rebase.sh` to keep it current with
`main`: it pulls `main`, rebases `dev` onto it, and force-pushes `dev`.

```bash
./link.sh
```

Symlinks `~/.config/omarchy/plugins/omaspeedmeter` to this repo, so Omarchy
loads the plugin straight from your working tree instead of a copy. Run
`./link.sh --remove` to remove the symlink.

```bash
omarchy restart shell
```

Restarts the [Omarchy shell](https://omarchy.org/manual/omarchy-cli/) to pick
up changes (`BarWidget.qml` is not hot-reloaded).

```bash
./format.sh
```

Formats the repo: [`qmlformat`](https://doc.qt.io/qt-6/qtqml-tooling-qmlformat.html)
for `BarWidget.qml`, [Prettier](https://prettier.io/) for Markdown/JSON/JS.
Run before committing.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for notable changes per version.

## License

This project is licensed under the [MIT License](LICENSE).
