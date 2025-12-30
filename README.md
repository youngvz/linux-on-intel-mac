## AMD eGPU (Thunderbolt) on Intel Mac mini 2018

This repository also documents a **working, stable configuration for using an AMD eGPU (Vega 56/64)** with Ubuntu on Intel Macs using Apple EFI.

This setup was validated on:

* **Mac mini 2018 (Coffee Lake, T2)**
* **Razer Core X**
* **AMD Radeon RX Vega 56**
* **Ubuntu 22.04 LTS**
* **Kernel 6.10.x**
* **External SSD boot**
* **rEFInd boot manager**
* **Apple EFI present (macOS retained on internal disk)**

The goal is **compute-only eGPU usage** with:

* Intel iGPU driving the desktop
* AMD eGPU available via `/dev/dri/render*`
* Stable cold boots
* No display flicker, hangs, or PCI enumeration failures

---

## Design principles

This setup intentionally avoids clever tricks in favor of **EFI-compatible, boring behavior**:

* No hotplug hacks
* No udev power overrides
* No amdgpu unload/reload loops
* No forced Thunderbolt authorization races
* No attempts to make the eGPU a primary display device

The eGPU is treated as **a secondary PCI device for compute**, not as a display controller.

---

## Working GRUB configuration (known-good)

The following GRUB configuration has proven **100% reliable** for cold boots, reboots, and kernel upgrades.

`/etc/default/grub`:

```ini
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`

GRUB_CMDLINE_LINUX="simpledrm=0 i915.modeset=1 amdgpu.dc=0 iommu=pt intel_iommu=on pci=realloc pci=nocrs pcie_ports=compat pcie_aspm=off modprobe.blacklist=brcmfmac,bcmdhd"
```

After editing:

```bash
sudo update-grub
sudo reboot
```

### Why these flags matter

* `simpledrm=0`
  Prevents early framebuffer handoff issues that cause green/purple flashing on Intel Macs.

* `i915.modeset=1`
  Ensures the Intel iGPU cleanly owns the display stack.

* `amdgpu.dc=0`
  Disables AMD Display Core. This avoids display init entirely while still allowing compute.

* `pci=realloc pci=nocrs`
  **Critical for eGPU stability.** Forces Linux to reassign PCI BARs instead of trusting Apple’s ACPI tables, which frequently under-allocate resources for GPUs behind Thunderbolt.

* `pcie_ports=compat`
  Improves compatibility with Thunderbolt PCI bridges on Apple firmware.

* `pcie_aspm=off`
  Avoids aggressive PCIe power management that can destabilize TB chains.

* `modprobe.blacklist=brcmfmac,bcmdhd`
  Prevents Broadcom Wi-Fi drivers from hanging early boot on T2 Macs. Ethernet is strongly recommended.

---

## Verified device layout

After boot, the system should report:

### Desktop renderer

```bash
glxinfo | grep -i "OpenGL renderer"
```

Expected:

```
Mesa Intel(R) UHD Graphics 630
```

### DRM device mapping

```bash
ls -l /dev/dri/by-path
```

Expected:

```
pci-0000:00:02.0-render -> /dev/dri/renderD128   # Intel iGPU
pci-0000:0d:00.0-render -> /dev/dri/renderD129   # AMD Vega eGPU
```

This mapping is **stable across reboots** and safe to reference directly from applications or containers.

---

## Things that were tried and explicitly did NOT work

The following approaches caused hangs, boot loops, or amdgpu initialization failures and are **intentionally avoided**:

* `amdgpu.modeset=0` (ignored by modern amdgpu, misleading)
* Forcing “compute-only” via `/etc/modprobe.d/amdgpu*.conf`
* Thunderbolt udev power rules
* systemd watchdogs that unload/reload `amdgpu`
* Hotplugging the eGPU during early boot
* Forcing the eGPU as a primary display
* `pci=assign-buses` / oversized HP bus memory tuning

While some of these may work on non-Apple hardware, they interact poorly with Apple EFI and Thunderbolt.

---

## Intended usage model

This configuration is ideal for:

* Frigate
* ffmpeg / VAAPI
* OpenCL / ROCm (Vega-compatible workloads)
* Containerized GPU workloads
* Headless or server-style usage

It is **not** intended for:

* External monitors driven by the eGPU
* Desktop GPU switching
* Gaming or Wayland display offload

---

## Summary

This setup demonstrates that **AMD eGPUs can be used reliably on Intel Macs under Linux** when:

* Apple EFI is respected rather than fought
* The iGPU owns display
* The eGPU is treated as compute hardware
* PCI resource allocation is handled explicitly

The result is a system that boots cleanly, survives kernel upgrades, and behaves predictably.

---
