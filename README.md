# 高质量<付费>中转站

https://sc.350303.xyz/register?aff=C8X8NEL4BXX6

# OpenWrt EasyMesh

这是一个面向家庭网络的 OpenWrt / ImmortalWrt Mesh 固件和 LuCI 管理项目。它提供 AC 控制器和 AP Agent，让多台路由器可以用同一套 Wi-Fi 配置、有线优先回程、无线 802.11s 兜底回程组成一个统一网络。

主要能力：

- AC 统一配置 2.4 GHz / 5 GHz SSID、密码、信道、漫游和无线回程参数
- AP 刷机后自动发现 AC、注册并拉取配置
- AP 的 WAN/LAN 都作为二层接入口使用，适合接到 AC 下级或同一局域网
- 有线回程优先，无线 Mesh 回程作为断线兜底
- 支持 AC 本机也作为 Mesh 成员发 Wi-Fi
- LuCI 页面入口：`Services -> EasyMesh`
- 默认集成 `ysuolmai/luci-theme-shadcn`

## 支持的固件

当前提供三类构建目标，每类都会同时构建 AC 和 AP：

```text
IPQ60XX-MESH-AC
IPQ60XX-MESH-AP
MT7981-MESH-AC
MT7981-MESH-AP
CLOSEWRT-MT7981-MESH-AC
CLOSEWRT-MT7981-MESH-AP
```

设备列表跟随上游配置全量选择，不再维护本仓库自己的设备白名单：

- IPQ60XX：来自 `ysuolmai/OpenWRT-CI` 的 `Config/IPQ60XX-WIFI-YES.txt`
- MT7981：来自 `ysuolmai/OpenWRT-CI` 的 `Config/MEDIATEK-WIFI-YES.txt`
- CloseWRT MT7981：来自 `ysuolmai/CloseWRT-CI` 的 `Config/MT7981.txt`

MTK 构建会保留并注入 `sx_7981r128` 设备支持。

## 怎么编译

在 GitHub Actions 手动运行对应 workflow：

- `Build All EasyMesh`：同时启动下面三类编译任务
- `Build IPQ EasyMesh`：构建 IPQ60XX AC/AP
- `Build MTK EasyMesh`：构建普通 MT7981 AC/AP
- `Build CloseWRT MTK EasyMesh`：构建 CloseWRT MT7981 AC/AP

运行 workflow 后会发布 release，里面包含生成后的 `.config` 和固件产物。如果只想检查配置是否能通过 `make defconfig`，运行 workflow 时勾选 `test_config_only`。

## 怎么用

1. 选择一台设备刷 AC 固件。
2. 进入 LuCI，打开 `Services -> EasyMesh`。
3. 配置 2.4 GHz / 5 GHz SSID、密码、国家码、信道、Mesh ID 和 Mesh Key。
4. 保存应用配置。
5. 其他设备刷 AP 固件，首次建议用网线接到 AC 或同一局域网。
6. AP 注册成功后会自动拉取 AC 配置并开始广播 Wi-Fi。
7. 后续可以拔掉 AP 网线，设备会切到无线 Mesh 回程；重新插回网线后会优先使用有线回程。

`Network mode` 可选：

- `Bridge`：AC、AP 和客户端都从上游 DHCP 获取地址，适合已有主路由的家庭网络。
- `Gateway`：AC 自己作为主路由提供 DHCP/NAT，AP 仍作为桥接节点。

## 源代码与致谢

本项目基于以下 OpenWrt / ImmortalWrt 源码构建：

- https://github.com/VIKINGYFY/immortalwrt.git
- https://github.com/Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly.git

感谢各位上游大佬的源码、驱动、设备适配和编译脚本。
