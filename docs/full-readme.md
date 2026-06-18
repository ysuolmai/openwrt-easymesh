# 高质量<付费>中转站

https://sc.350303.xyz/register?aff=C8X8NEL4BXX6

# OpenWrt EasyMesh

一个基于 OpenWrt / ImmortalWrt 的 Mesh AC + AP 管理项目，当前支持 IPQ60XX 和 MT7981。

当前目标不是一次性做完整商用 Mesh 系统，而是先做一个可编译、可配对、可下发配置的 MVP：

- AC 负责管理配置、显示 AP、控制新 AP 配对窗口、下发参数
- AP 刷入托管固件后自动向 AC 注册
- 第一次建议通过有线连接完成配对
- 配对后 AP 保存配置，即使 AC 暂时离线也继续工作
- 有线回程优先，无线 802.11s 回程作为兜底
- Wi-Fi 漫游使用 OpenWrt 的 `wpad` + 802.11k/v/r，客户端状态/漫游引导复用 DAWN
- AC 如果本身带 Wi-Fi，也可以作为本地 Mesh 成员加入同一套回程，并按 2.4 GHz / 5 GHz 配置客户端 SSID

## 架构

```text
主路由 / AC
    |
    | 有线 LAN，首次配对和优先回程
    |
托管 AP 1  )) 802.11s wireless backhaul ))  托管 AP 2
    |
2.4 GHz / 5 GHz 客户端 Wi-Fi SSID
```

AC 可以是负责拨号和 DHCP 的主路由，也可以只是挂在现有主路由下面的桥接节点。AP 不负责拨号、DHCP 或 NAT；配对前后都会把 WAN/LAN 当作同一个二层接入口。

AC 的 `Network mode` 控制本机网络角色：`Bridge` 模式下 WAN、LAN、Wi-Fi 和 Mesh 回程都桥到同一个 LAN，客户端地址来自上游 DHCP；`Gateway` 模式下 AC 保留 WAN 上联并在 LAN 侧提供 DHCP，AP 仍然作为桥接节点接入 AC LAN。

## 组件

### `easymesh-controller`

运行在 AC 设备上：

- 保存全局 Mesh 配置
- 接收 AP 注册
- 维护 AP 列表
- 通过 `Allow pairing` 控制新 AP 注册
- 通过 CGI API 下发 AP 配置

### `easymesh-local-member`

可选包，适合有 Wi-Fi 的 AC：

- 让 AC 本机 Wi-Fi 也作为 Mesh 成员加入同一套回程
- 根据本机是否存在 Wi-Fi 驱动或 `/etc/config/wireless` 决定是否执行
- `local_member=0` 时写入 `ath11k nss_offload=1 frame_mode=2`
- `local_member=1` 时写入 `ath11k nss_offload=0 frame_mode=2`，并应用 AC 本机 Wi-Fi / 802.11s / batman 配置；如果 ath11k 模块已加载且参数无法热切换，会自动安排一次重启让模块参数生效
- IPQ AP 固件默认写入 `ath11k nss_offload=0 frame_mode=2`；IPQ AC 固件默认关闭，之后由 `local_member` 状态切换

### `luci-app-easymesh`

AC 的 LuCI 管理页面：

- 配置 2.4 GHz / 5 GHz 客户端 SSID / 密码
- 配置无线回程 `mesh_id` / `mesh_key`
- 配置 802.11k/v/r
- 配置 DAWN 开关
- 查看 AP 在线状态和最后上报时间
- 有本机 Wi-Fi 和 `easymesh-local-member` 时，显示 AC 本地 Mesh 成员模式，表单优先读取本机实际生效配置
- no-wifi / controller-only 固件中，页面只显示纯 AC 控制器配置和 AP 列表

页面路径：

```text
Services -> EasyMesh
```

### `easymesh-agent`

运行在 AP 设备上：

- 启动后向 AC 注册
- 注册成功后拉取 AC 下发的配置
- 写入 OpenWrt UCI 配置
- 生成 2.4 GHz / 5 GHz AP SSID、802.11s 回程、batman-adv、DAWN 参数
- 在 AC 本地成员模式下可用 `--local-ac` 按 `Bridge` 或 `Gateway` 网络模式应用本机配置

## 固件目标

当前提供三组平台目标。每个平台都同时提供 AC 和 AP 包，设备 profile 不再使用本仓库自己的设备子集，而是跟随 `ysuolmai/OpenWRT-CI` 里的上游配置文件。

IPQ60XX：

```text
IPQ60XX-MESH-AC
IPQ60XX-MESH-AP
```

设备列表来源：`Config/IPQ60XX-WIFI-YES.txt`。完整展开列表以 `configs/IPQ60XX-MESH-*.txt` 为准。

MT7981：

```text
MT7981-MESH-AC
MT7981-MESH-AP
```

设备列表来源：`Config/MEDIATEK-WIFI-YES.txt`。完整展开列表以 `configs/MT7981-MESH-*.txt` 为准，并保留上游配置里的 `kmod-cryptodev` / `kmod-tls` 内核调整。


CloseWRT MT7981：

```text
CLOSEWRT-MT7981-MESH-AC
CLOSEWRT-MT7981-MESH-AP
```

设备列表来源：`ysuolmai/CloseWRT-CI` 的 `Config/MT7981.txt`，完整展开列表以 `configs/CLOSEWRT-MT7981-MESH-*.txt` 为准，并保留 `sx_7981r128` 的 CloseWRT 6.6 DTS、PHY patch 和设备 profile 注入。

其中 `sx_7981r128` 不是 `VIKINGYFY/immortalwrt` 源码自带 profile，本项目会在准备配置阶段按上游机制注入 DTS、`filogic.mk` 设备条目、基础网络和首次启动配置。

## 编译

仓库使用 GitHub Actions 手动编译，避免占用过多 cache。

默认源码是：

```text
https://github.com/VIKINGYFY/immortalwrt.git
```

IPQ workflow 默认分支是 `main`，并按上游 `Config/IPQ60XX-WIFI-YES.txt` 的设备列表选择 profile；各设备需要的 `ipq-wifi-*` BDF 包由对应 profile 选择。

MTK workflow 单独放在 `.github/workflows/build-mtk.yml`，默认分支是 `owrt`，跟随上游 `MTK-ALL.yml`。CloseWRT 闭源 MTK SDK workflow 单独放在 `.github/workflows/build-closewrt-mtk.yml`，默认源码跟随 `ysuolmai/CloseWRT-CI` 当前使用的 `Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly` / `openwrt-24.10-6.6`。

workflow 参考上游 OpenWRT-CI 启用构建缓存：非 `test_config_only` 构建会缓存 `.ccache`、`staging_dir/host*` 和 `staging_dir/tool*`，并在恢复缓存后刷新 toolchain stamp，减少重复编译时间。

`make defconfig` 后 workflow 会运行对应 checker：普通 IPQ/MTK 使用 `scripts/check-openwrt-config.sh`，CloseWRT MTK 使用 `scripts/check-closewrt-config.sh`。它们会主动检查以下关键内容：

- 目标设备 profile 是否包含 `configs/*.txt` 中同步自上游的完整设备列表
- IPQ：`kmod-ath11k-ahb` / `kmod-ath11k-pci`、IPQ6018 firmware；各设备 BDF 包由设备 profile 选择
- IPQ AC/AP：额外检查 ath11k NSS mesh offload 所需的 `ATH11K_NSS_MESH_SUPPORT`、`kmod-qca-nss-drv-wifi-meshmgr` 和 NSS Wi-Fi mesh driver flags
- MTK：普通 MTK 检查 `kmod-mt7915e`、`kmod-mt7981-firmware`、`mt7981-wo-firmware`、`kmod-cryptodev`、`kmod-tls`；CloseWRT MTK 检查闭源 MTK Wi-Fi 栈和 `sx_7981r128` 注入
- `wpad-openssl`
- `batman-adv` / `batctl`
- DAWN / uMDNS
- LuCI AC 应用、自研 `easymesh-controller` / `easymesh-local-member` / `easymesh-agent`、shadcn LuCI 主题

IPQ 编译：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Build IPQ EasyMesh`
3. 点击 `Run workflow`
4. workflow 会同时构建 `IPQ60XX-MESH-AC` 和 `IPQ60XX-MESH-AP`
5. 如只想验证配置，勾选 `test_config_only`

MTK 编译：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Build MTK EasyMesh`
3. 点击 `Run workflow`
4. workflow 会同时构建 `MT7981-MESH-AC` 和 `MT7981-MESH-AP`
5. 如只想验证配置，勾选 `test_config_only`

一键同时启动三类编译：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Build All EasyMesh`
3. 点击 `Run workflow`
4. workflow 会并行启动 IPQ、MTK、CloseWRT MTK 三类编译；每类内部继续同时构建 AC 和 AP
5. 如只想验证配置，勾选 `test_config_only`

CloseWRT MTK 编译：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Build CloseWRT MTK EasyMesh`
3. 点击 `Run workflow`
4. workflow 会同时构建 `CLOSEWRT-MT7981-MESH-AC` 和 `CLOSEWRT-MT7981-MESH-AP`
5. 如只想验证配置，勾选 `test_config_only`

AC 和 AP 固件都会按上游 OpenWRT-CI 的方式注入 `ysuolmai/luci-theme-shadcn`，并默认启用 shadcn LuCI 主题。

workflow 会发布：

- 生成后的 `.config`
- `bin/targets` 下除 `packages` 目录外的固件产物
- manifest / buildinfo / sha256sums

IPQ NAND 设备如 Redmi AX5 和 ZN M2 走上游 `Device/UbiFit`，factory 首刷镜像是 `factory.ubi`；workflow 按上游方式收集目标目录产物，避免按后缀白名单漏掉 factory。

## 清理

仓库提供独立的 `Clean Artifacts` workflow，用于释放 GitHub Actions 和 release 空间：

- 删除所有已完成的 workflow run
- 删除所有 `Test config only: true` 的 release 和对应 tag
- 正式固件 release 按每个配置目标只保留最新一版，默认每个目标保留 1 个

操作方式：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Clean Artifacts`
3. 点击 `Run workflow`
4. 如只想预览，启用 `dry_run`

正式固件保留策略按配置目标分组，例如 `IPQ60XX-MESH-AC`、`IPQ60XX-MESH-AP`、`MT7981-MESH-AC`、`MT7981-MESH-AP` 会分别保留最新一版。

## 首次使用

### 1. 刷 AC 固件

选择一台设备刷入对应平台的 AC 固件：

```text
IPQ60XX-MESH-AC
MT7981-MESH-AC
```

进入 LuCI 后打开：

```text
Services -> EasyMesh
```

建议先修改：

```text
2.4 GHz client SSID
5 GHz client SSID
Client password
Mesh ID
Mesh key
Country
5 GHz channel
2.4 GHz channel
```

页面打开时，表单字段会优先读取设备当前实际生效的网络和 Wi-Fi 状态；如果某项没有实时状态可读，就回退到 `/etc/config/easymesh` 里的保存值，避免页面显示旧值。

`Network mode` 默认是 `Gateway`：AC 使用 192.168.10.1/24 并在 LAN 侧提供 DHCP。若 AC 要挂在现有主路由下，把它改成 `Bridge`。

当前 AC 固件包含 `easymesh-local-member`。点击 LuCI 底部 `Save & Apply` 后，如果机器有本机 Wi-Fi，AC 会按 `Network mode` 应用 WAN/LAN 桥接或网关网络。`Enable AC local mesh member` 关闭时会写入 `ath11k nss_offload=1 frame_mode=2`；如果这台 AC 本身也要发 Wi-Fi / 加入 Mesh，再打开该选项，应用时会写入 `ath11k nss_offload=0 frame_mode=2`；如果 ath11k 模块已加载且参数无法热切换，会自动重启一次，重启后继续应用本机 Mesh 配置，并清理默认 `ImmortalWrt` 等 LAN AP SSID，按 2.4 GHz / 5 GHz 各自的 SSID 创建客户端 Wi-Fi、802.11s 回程、`batman-adv` 和 DAWN 配置。

如果在其他 no-wifi 编译项目中只安装 `easymesh-controller` + `luci-app-easymesh`，它就是纯 AC 控制器插件，不依赖 Wi-Fi / `easymesh-agent` / `batman-adv`，LuCI 也不会显示本机 Mesh 成员相关界面。

## 作为插件加入其他编译项目

还是使用这个仓库：`https://github.com/ysuolmai/openwrt-easymesh`。

如果只是想把 AC 管理功能加到其他 OpenWrt / ImmortalWrt 编译项目里，可以把本仓库的 `package/` 目录作为自定义包导入。最简单的做法是在目标源码树里执行：

```sh
git clone --depth=1 https://github.com/ysuolmai/openwrt-easymesh.git /tmp/openwrt-easymesh
mkdir -p package/openwrt-easymesh
cp -R /tmp/openwrt-easymesh/package/. package/openwrt-easymesh/
```

然后按需要选择包组合。

纯 AC 控制器，适合无 Wi-Fi 硬件、no-wifi 固件、软路由或旁路 AC：

```text
CONFIG_PACKAGE_easymesh-controller=y
CONFIG_PACKAGE_luci-app-easymesh=y
CONFIG_PACKAGE_umdns=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
```

Full AC，适合 AC 本机也有 Wi-Fi、可能作为 Mesh 成员加入回程：

```text
CONFIG_PACKAGE_easymesh-controller=y
CONFIG_PACKAGE_easymesh-local-member=y
CONFIG_PACKAGE_luci-app-easymesh=y
CONFIG_PACKAGE_easymesh-agent=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_kmod-batman-adv=y
CONFIG_PACKAGE_batctl-default=y
CONFIG_PACKAGE_dawn=y
CONFIG_PACKAGE_umdns=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
```

托管 AP 固件需要：

```text
CONFIG_PACKAGE_easymesh-agent=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_kmod-batman-adv=y
CONFIG_PACKAGE_batctl-default=y
CONFIG_PACKAGE_dawn=y
CONFIG_PACKAGE_umdns=y
CONFIG_PACKAGE_iw=y
```

如果目标项目也想使用同款 shadcn 主题，请使用我的 fork：

```sh
git clone --depth=1 https://github.com/ysuolmai/luci-theme-shadcn.git package/luci-theme-shadcn
```

并在配置里启用：

```text
CONFIG_PACKAGE_luci-theme-bootstrap=n
CONFIG_PACKAGE_luci-theme-shadcn=y
```

`luci-app-easymesh` 是同一套页面。它会通过 `/usr/sbin/easymesh-status` 自动检测本机是否有 Wi-Fi 驱动或 `/etc/config/wireless`，以及是否安装了 `easymesh-local-member`：检测不到时就是纯 AC 界面；检测到时才显示 `Enable AC local mesh member`、`Network mode` ，并优先读取本机实际生效配置。

### 2. 刷 AP 固件

其他节点刷入对应平台的 AP 固件：

```text
IPQ60XX-MESH-AP
MT7981-MESH-AP
```

AP 固件首次启动会先进入安全的桥接接入状态：关闭本机 LAN DHCP，把 WAN/LAN 当作同一个二层接入口，并清理默认 LAN Wi-Fi AP。刷完后可以把 AP 的 WAN 或 LAN 接到 AC 下游，也可以接到 AC 所在的同一个上游局域网。

AP 默认通过 mDNS 自动发现 AC,无需手动配置地址，也不需要单独设置配对 token。发现顺序:

1. 显式配置的 `ac_url`(若可达)
2. AC 通过 umdns 广播的 `_easymesh._tcp` 服务
3. 默认网关(AC 兼作主路由时)
4. 上次成功连接的缓存地址
5. 兜底地址 `http://192.168.10.1/cgi-bin/easymesh`

如果要把 AP 固定到某台 AC,可手动指定:

```sh
uci set easymesh_agent.main.ac_url='http://AC_IP/cgi-bin/easymesh'
uci commit easymesh_agent
/etc/init.d/easymesh-agent restart
```

只想用静态地址、关闭自动发现,可设 `uci set easymesh_agent.main.ac_discovery='static'`。

### 3. 有线配对

把 AP 用网线接入 AC 所在网络。AP 的 WAN 口或 LAN 口都可以使用；在桥接模式下它们都会进入同一个 `br-lan`。

当 AC 的 `Allow pairing` 开启时，新 AP 会自动注册并拉取配置；关闭后只接受已经出现过的 AP 继续上报和拉取配置。AP 应用后会生成：

- 2.4 GHz / 5 GHz 客户端 Wi-Fi SSID
- 802.11k/v/r
- 802.11s 无线回程
- batman-adv
- DAWN

### 4. 无线回程

AP 配对成功后，可以拔掉网线。

AP 会保留无线 802.11s 回程配置，后续可通过无线回到 Mesh 网络。

当前有线和无线回程会同时保留，二层环路由 batman-adv 的 bridge loop avoidance(BLA)处理。`Prefer wired backhaul` 开启时，AP/AC 会启动 `easymesh-backhaul` watchdog：检测有线桥端口 carrier 变化，主动 flush bridge FDB/邻居表并触发 LAN renew/ping，让路径从有线切到无线或从无线切回有线时尽快重新学习。它不会把无线 mesh 从 batman-adv 拆掉，所以不会造成下游无线 AP 无法重新入网的死锁。更彻底的方案仍然是后续把专用上联口建成 batman hardif 并用 hop penalty 偏向有线。

## 当前限制

v0.1 还是脚手架，重点是先把 AC/AP 架构跑通：

- 配对控制目前是家庭网络用的简单模式：`Allow pairing` 开启时允许新 AP 注册，关闭后只保留已知 AP
- AC 自动发现已用 mDNS 实现，AP 也可手动固定 `ac_url`
- 有线和无线回程同时保留，环路靠 BLA；当前已用 `easymesh-backhaul` 加速桥学习收敛，完整 batman hardif + hop penalty 方案仍待真机验证
- LuCI 页面目前只做基础配置、AP 在线/最后上报时间、AC 本机 Mesh 应用
- 还没有拓扑图、链路质量、在线状态详情
- 需要真机验证 IPQ60XX / MT7981 上的 802.11s、DAWN 和 KVR 组合

## 目录

```text
configs/                 OpenWrt 构建配置
package/easymesh-controller/         AC 服务
package/easymesh-local-member/ AC 本机 Mesh 成员可选包
package/easymesh-agent/      AP agent
package/luci-app-easymesh LuCI 管理页面
scripts/                 构建准备脚本
.github/workflows/       GitHub Actions 编译流程
docs/                    设计说明
```

## 状态

当前已经进入真机调试阶段：

1. 项目和 OpenWrt 包已统一为 EasyMesh 命名体系，不保留历史包名兼容。
2. IPQ60XX / MT7981 的 AC、AP 构建配置都已接入新的 `easymesh-*` 包名。
3. AC / AP 支持桥接接入，WAN/LAN 可作为同一二层入口使用。
4. AC 可作为纯控制器，也可在有 Wi-Fi 时启用本地 Mesh 成员。
5. AP 支持 mDNS 自动发现 AC、拉取配置、应用 2.4 GHz / 5 GHz 独立 SSID、802.11s 回程、batman-adv 和 DAWN。

仍需继续验证：

1. 最新 rename 后的完整 GitHub Actions 编译。
2. IPQ60XX / MT7981 真机上的无线回程稳定性。
3. 有线优先目前是桥层快速收敛方案；完整 batman hardif + hop penalty 方案仍需真机验证。
4. 拓扑、链路质量和更完整的在线状态展示。
