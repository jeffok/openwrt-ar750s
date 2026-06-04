#!/usr/bin/env python3
# ath79(mipsle softfloat) 使用 MetaCubeX 预编译 mihomo，避免 LEDE 交叉编译 gvisor/tailscale 失败
from pathlib import Path


def patch_meta(openwrt: Path) -> None:
    p = openwrt / "feeds/mihomo/mihomo-meta/Makefile"
    text = p.read_text()
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
        "# ath79：使用 MetaCubeX 官方 mipsle-softfloat 预编译内核\n"
        "ifeq ($(CONFIG_TARGET_ath79),y)\n"
        "MIHOMO_PREBUILT_ARCH:=mipsle-softfloat\n"
        "define Download/mihomo-prebuilt\n"
        "\tURL:=https://github.com/MetaCubeX/mihomo/releases/download/$(PKG_BUILD_VERSION)/\n"
        "\tFILE:=mihomo-linux-$(MIHOMO_PREBUILT_ARCH)-$(PKG_BUILD_VERSION).gz\n"
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
    if old not in text:
        raise SystemExit("mihomo-meta Makefile anchor not found")
    p.write_text(text.replace(old, new, 1))
    print("Patched mihomo-meta: ath79 uses prebuilt mipsle-softfloat binary")


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
    if old not in text:
        raise SystemExit("nikki Makefile anchor not found")
    p.write_text(text.replace(old, new, 1))
    print("Patched nikki: ath79 skips Go source build (uses mihomo-meta binary)")


def main() -> None:
    import sys

    root = Path(sys.argv[1] if len(sys.argv) > 1 else "openwrt")
    patch_meta(root)
    patch_nikki(root)


if __name__ == "__main__":
    main()
