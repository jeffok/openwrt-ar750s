#!/usr/bin/env python3
# ath79(mipsle softfloat)：mihomo-meta / yq 使用官方预编译二进制，避免 LEDE 交叉编译 Go 失败
from __future__ import annotations

import hashlib
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


def fetch_sha256(url: str) -> str:
    """下载预编译包并计算 SHA256（供 OpenWrt Download HASH 使用）"""
    req = urllib.request.Request(url, headers={"User-Agent": "openwrt-ar750s-ci"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    if len(data) < 1024:
        raise SystemExit(f"download too small: {url} ({len(data)} bytes)")
    return hashlib.sha256(data).hexdigest()


def read_var(makefile: str, name: str) -> str:
    m = re.search(rf"^{re.escape(name)}:=([^\n]+)", makefile, re.M)
    if not m:
        raise SystemExit(f"{name} not found in Makefile")
    return m.group(1).strip()


def patch_meta(openwrt: Path) -> None:
    p = openwrt / "feeds/mihomo/mihomo-meta/Makefile"
    text = p.read_text()
    ver = read_var(text, "PKG_VERSION")
    build_ver = read_var(text, "PKG_BUILD_VERSION")
    arch = "mipsle-softfloat"
    fname = f"mihomo-linux-{arch}-{build_ver}.gz"
    url = f"https://github.com/MetaCubeX/mihomo/releases/download/{build_ver}/{fname}"
    sha = fetch_sha256(url)
    print(f"mihomo-meta {build_ver}: {fname} sha256={sha}")

    old = (
        "define Build/Prepare\n"
        "\t$(Build/Prepare/Default)\n"
        "\t$(RM) -r $(PKG_BUILD_DIR)/rules/logic_test\n"
        "endef\n"
        "\n"
        "$(eval $(call GoBinPackage,mihomo-meta))\n"
        "$(eval $(call BuildPackage,mihomo-meta))\n"
    )
    new = (
        "define Build/Prepare\n"
        "\t$(Build/Prepare/Default)\n"
        "\t$(RM) -r $(PKG_BUILD_DIR)/rules/logic_test\n"
        "endef\n"
        "\n"
        "# ath79：MetaCubeX 官方 mipsle-softfloat 预编译（避免 gvisor/tailscale 交叉编译失败）\n"
        "ifeq ($(CONFIG_TARGET_ath79),y)\n"
        f"MIHOMO_PREBUILT_ARCH:={arch}\n"
        "define Download/mihomo-prebuilt\n"
        f"\tURL:=https://github.com/MetaCubeX/mihomo/releases/download/$(PKG_BUILD_VERSION)/\n"
        f"\tFILE:=mihomo-linux-$(MIHOMO_PREBUILT_ARCH)-$(PKG_BUILD_VERSION).gz\n"
        f"\tHASH:={sha}\n"
        "endef\n"
        "$(eval $(call Download,mihomo-prebuilt))\n"
        "define Build/Compile\n"
        "\t$(INSTALL_DIR) $(PKG_BUILD_DIR)/usr/libexec\n"
        "\tgzip -dc $(DL_DIR)/mihomo-linux-$(MIHOMO_PREBUILT_ARCH)-$(PKG_BUILD_VERSION).gz \\\n"
        "\t\t> $(PKG_BUILD_DIR)/usr/libexec/mihomo\n"
        "\tchmod +x $(PKG_BUILD_DIR)/usr/libexec/mihomo\n"
        "endef\n"
        "define Package/mihomo-meta/install\n"
        "\t$(INSTALL_DIR) $(1)/usr/libexec\n"
        "\t$(INSTALL_BIN) $(PKG_BUILD_DIR)/usr/libexec/mihomo $(1)/usr/libexec/mihomo\n"
        "endef\n"
        "$(eval $(call BuildPackage,mihomo-meta))\n"
        "else\n"
        "$(eval $(call GoBinPackage,mihomo-meta))\n"
        "$(eval $(call BuildPackage,mihomo-meta))\n"
        "endif\n"
    )
    if "MIHOMO_PREBUILT_ARCH:=mipsle-softfloat" in text and "Download/mihomo-prebuilt" in text:
        print("mihomo-meta already patched, skip")
        return
    if old not in text:
        raise SystemExit("mihomo-meta Makefile anchor not found")
    p.write_text(text.replace(old, new, 1))
    print("Patched mihomo-meta: ath79 prebuilt with HASH")


def patch_nikki(openwrt: Path) -> None:
    p = openwrt / "feeds/mihomo/nikki/Makefile"
    text = p.read_text()
    old = (
        "$(eval $(call GoBinPackage,nikki))\n"
        "$(eval $(call BuildPackage,nikki))\n"
    )
    new = (
        "ifeq ($(CONFIG_TARGET_ath79),y)\n"
        "$(eval $(call BuildPackage,nikki))\n"
        "else\n"
        "$(eval $(call GoBinPackage,nikki))\n"
        "$(eval $(call BuildPackage,nikki))\n"
        "endif\n"
    )
    if "ifeq ($(CONFIG_TARGET_ath79),y)\n$(eval $(call BuildPackage,nikki))" in text.replace("\r\n", "\n"):
        print("nikki already patched, skip")
        return
    if old not in text:
        raise SystemExit("nikki Makefile anchor not found")
    p.write_text(text.replace(old, new, 1))
    print("Patched nikki: ath79 skips Go build")


def patch_yq(openwrt: Path) -> None:
    p = openwrt / "feeds/packages/utils/yq/Makefile"
    if not p.exists():
        raise SystemExit(f"yq Makefile not found: {p}")
    text = p.read_text()
    ver = read_var(text, "PKG_VERSION")
    fname = "yq_linux_mipsle"
    url = f"https://github.com/mikefarah/yq/releases/download/v{ver}/{fname}"
    sha = fetch_sha256(url)
    print(f"yq v{ver}: {fname} sha256={sha}")

    old = (
        "$(eval $(call GoBinPackage,yq))\n"
        "$(eval $(call BuildPackage,yq))\n"
    )
    new = (
        "# ath79：官方 mipsle 预编译，避免 yq Go 交叉编译失败\n"
        "ifeq ($(CONFIG_TARGET_ath79),y)\n"
        "define Download/yq-prebuilt\n"
        f"\tURL:=https://github.com/mikefarah/yq/releases/download/v$(PKG_VERSION)/\n"
        f"\tFILE:={fname}\n"
        f"\tHASH:={sha}\n"
        "endef\n"
        "$(eval $(call Download,yq-prebuilt))\n"
        "define Build/Compile\n"
        "\t$(INSTALL_DIR) $(PKG_BUILD_DIR)\n"
        f"\t$(CP) $(DL_DIR)/{fname} $(PKG_BUILD_DIR)/yq\n"
        "\tchmod +x $(PKG_BUILD_DIR)/yq\n"
        "endef\n"
        "define Package/yq/install\n"
        "\t$(INSTALL_DIR) $(1)/usr/bin\n"
        "\t$(INSTALL_BIN) $(PKG_BUILD_DIR)/yq $(1)/usr/bin/yq\n"
        "endef\n"
        "$(eval $(call BuildPackage,yq))\n"
        "else\n"
        "$(eval $(call GoBinPackage,yq))\n"
        "$(eval $(call BuildPackage,yq))\n"
        "endif\n"
    )
    if "Download/yq-prebuilt" in text:
        print("yq already patched, skip")
        return
    if old not in text:
        raise SystemExit("yq Makefile anchor not found")
    p.write_text(text.replace(old, new, 1))
    print("Patched yq: ath79 prebuilt with HASH")


def prefetch_dl(openwrt: Path) -> None:
    """提前写入 dl/，编译阶段 download.pl 可直接命中缓存"""
    dl = openwrt / "dl"
    dl.mkdir(exist_ok=True)

    meta_mk = (openwrt / "feeds/mihomo/mihomo-meta/Makefile").read_text()
    build_ver = read_var(meta_mk, "PKG_BUILD_VERSION")
    arch = "mipsle-softfloat"
    mfile = f"mihomo-linux-{arch}-{build_ver}.gz"
    murl = f"https://github.com/MetaCubeX/mihomo/releases/download/{build_ver}/{mfile}"
    mp = dl / mfile
    if not mp.exists() or mp.stat().st_size < 1024:
        print(f"Prefetch {mfile} ...")
        req = urllib.request.Request(murl, headers={"User-Agent": "openwrt-ar750s-ci"})
        mp.write_bytes(urllib.request.urlopen(req, timeout=120).read())
    print(f"dl/{mfile}: {mp.stat().st_size} bytes")

    yq_mk = (openwrt / "feeds/packages/utils/yq/Makefile").read_text()
    yver = read_var(yq_mk, "PKG_VERSION")
    yfile = "yq_linux_mipsle"
    yurl = f"https://github.com/mikefarah/yq/releases/download/v{yver}/{yfile}"
    yp = dl / yfile
    if not yp.exists() or yp.stat().st_size < 1024:
        print(f"Prefetch {yfile} ...")
        req = urllib.request.Request(yurl, headers={"User-Agent": "openwrt-ar750s-ci"})
        yp.write_bytes(urllib.request.urlopen(req, timeout=120).read())
    print(f"dl/{yfile}: {yp.stat().st_size} bytes")


def main() -> None:
    args = sys.argv[1:]
    prefetch_only = False
    if args and args[-1] == "--prefetch-only":
        prefetch_only = True
        args = args[:-1]
    root = Path(args[0] if args else "openwrt")
    try:
        if not prefetch_only:
            patch_meta(root)
            patch_nikki(root)
            patch_yq(root)
        prefetch_dl(root)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} fetching prebuilt: {e.url}") from e


if __name__ == "__main__":
    main()
