#!/bin/bash
# feeds 安装完成后执行的自定义脚本
#
# coolsnowwolf/lede 默认 feeds 已包含全部所需包，无需额外注入第三方源：
#   - coolsnowwolf/luci (openwrt-25.12)：homeproxy、smartdns、passwall、diskman 等
#   - coolsnowwolf/packages：sing-box 及所有运行时依赖


# 将 LuCI 主题设为 argon（比默认 bootstrap 更现代，需在 .config 中同时启用该包）
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
