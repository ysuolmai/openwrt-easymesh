# OpenWrt Mesh AC

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

### `mesh-ac`

运行在 AC 设备上：

- 保存全局 Mesh 配置
- 接收 AP 注册
- 维护 AP 列表
- 通过 `Allow pairing` 控制新 AP 注册
- 通过 CGI API 下发 AP 配置
- 可把 AC 本机 Wi-Fi 应用为本地 Mesh 成员

### `luci-app-mesh-ac`

AC 的 LuCI 管理页面：

- 配置 2.4 GHz / 5 GHz 客户端 SSID / 密码
- 配置无线回程 `mesh_id` / `mesh_key`
- 配置 802.11k/v/r
- 配置 DAWN 开关
- 查看 AP 在线状态和最后上报时间
- 启用 AC 本地 Mesh 成员模式
- 底部 Save & Apply 会应用 AC 本机 Wi-Fi / Mesh / 网络模式配置

页面路径：

```text
Services -> Mesh AC
```

### `mesh-agent`

运行在 AP 设备上：

- 启动后向 AC 注册
- 注册成功后拉取 AC 下发的配置
- 写入 OpenWrt UCI 配置
- 生成 2.4 GHz / 5 GHz AP SSID、802.11s 回程、batman-adv、DAWN 参数
- 在 AC 本地成员模式下可用 `--local-ac` 按 `Bridge` 或 `Gateway` 网络模式应用本机配置

## 固件目标

当前提供两组平台目标。

IPQ60XX：

```text
IPQ60XX-MESH-AC
IPQ60XX-MESH-AP
```

设备白名单：

```text
redmi_ax5
redmi_ax5-jdcloud
jdcloud_re-ss-01
qihoo_360v6
zn_m2
```

MT7981：

```text
MT7981-MESH-AC
MT7981-MESH-AP
```

MTK 设备白名单跟随上游 `OpenWRT-CI/Scripts/diy.sh`：

```text
sx_7981r128
nokia_ea0326gmp
cmcc_rax3000m
```

其中 `sx_7981r128` 不是 `VIKINGYFY/immortalwrt` 源码自带 profile，本项目会在准备配置阶段按上游机制注入 DTS、`filogic.mk` 设备条目、基础网络和首次启动配置。

## 编译

仓库使用 GitHub Actions 手动编译，避免占用过多 cache。

默认源码是：

```text
https://github.com/VIKINGYFY/immortalwrt.git
```

IPQ workflow 默认分支是 `main`，因为该 fork 包含 `redmi_ax5`、`redmi_ax5-jdcloud`、`zn_m2` 等扩展 IPQ60XX 设备 profile 和对应 `ipq-wifi-*` BDF 包。

MTK workflow 单独放在 `.github/workflows/build-mtk.yml`，默认分支是 `owrt`，跟随上游 `MTK-ALL.yml`。

workflow 参考上游 OpenWRT-CI 启用构建缓存：非 `test_config_only` 构建会缓存 `.ccache`、`staging_dir/host*` 和 `staging_dir/tool*`，并在恢复缓存后刷新 toolchain stamp，减少重复编译时间。

`make defconfig` 后 workflow 会运行 `scripts/check-openwrt-config.sh`，主动检查以下关键内容：

- 目标设备 profile 是否存在
- IPQ：`kmod-ath11k-ahb` / `kmod-ath11k-pci`、IPQ6018 firmware、各设备 `ipq-wifi-*` BDF 包
- MTK：`kmod-mt7915e`、`kmod-mt7981-firmware`、`mt7981-wo-firmware`
- `wpad-openssl`
- `batman-adv` / `batctl`
- DAWN / uMDNS
- LuCI AC 应用、自研 `mesh-ac` / `mesh-agent`、shadcn LuCI 主题

IPQ 编译：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Build IPQ Mesh`
3. 点击 `Run workflow`
4. workflow 会同时构建 `IPQ60XX-MESH-AC` 和 `IPQ60XX-MESH-AP`
5. 如只想验证配置，勾选 `test_config_only`

MTK 编译：

1. 打开 GitHub 仓库的 `Actions`
2. 选择 `Build MTK Mesh`
3. 点击 `Run workflow`
4. workflow 会同时构建 `MT7981-MESH-AC` 和 `MT7981-MESH-AP`
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
Services -> Mesh AC
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

页面顶部的 `Current active state` 显示设备当前实际生效的网络和 Wi-Fi 状态。`Network mode` 默认按实际状态初始化，避免 `/etc/config/mesh_ac` 中的期望值和系统当前网络状态不一致时误导操作。

`Network mode` 默认是 `Bridge`：AC 的 WAN/LAN、客户端 Wi-Fi 和 Mesh 回程会处在同一个二层 LAN，客户端地址来自上游 DHCP。如果 AC 要作为主路由提供 DHCP/NAT，改成 `Gateway`。

点击 LuCI 底部 `Save & Apply` 后，AC 会按 `Network mode` 应用 WAN/LAN 桥接或网关网络。`Enable AC local mesh member` 默认关闭，此时 AC 保持 ath11k NSS offload 开启；如果这台 AC 本身也要发 Wi-Fi / 加入 Mesh，再打开该选项，应用时会关闭 ath11k NSS offload，并清理默认 `ImmortalWrt` 等 LAN AP SSID，按 2.4 GHz / 5 GHz 各自的 SSID 创建客户端 Wi-Fi、802.11s 回程、`batman-adv` 和 DAWN 配置。

### 2. 刷 AP 固件

其他节点刷入对应平台的 AP 固件：

```text
IPQ60XX-MESH-AP
MT7981-MESH-AP
```

AP 固件首次启动会先进入安全的桥接接入状态：关闭本机 LAN DHCP，把 WAN/LAN 当作同一个二层接入口，并清理默认 LAN Wi-Fi AP。刷完后可以把 AP 的 WAN 或 LAN 接到 AC 下游，也可以接到 AC 所在的同一个上游局域网。

AP 默认通过 mDNS 自动发现 AC,无需手动配置地址，也不需要单独设置配对 token。发现顺序:

1. 显式配置的 `ac_url`(若可达)
2. AC 通过 umdns 广播的 `_mesh-ac._tcp` 服务
3. 默认网关(AC 兼作主路由时)
4. 上次成功连接的缓存地址
5. 兜底地址 `http://192.168.50.1/cgi-bin/mesh-ac`

如果要把 AP 固定到某台 AC,可手动指定:

```sh
uci set mesh_agent.main.ac_url='http://AC_IP/cgi-bin/mesh-ac'
uci commit mesh_agent
/etc/init.d/mesh-agent restart
```

只想用静态地址、关闭自动发现,可设 `uci set mesh_agent.main.ac_discovery='static'`。

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

当前有线和无线回程同时挂在 batman-adv 上，二层环路由 batman-adv 的 bridge loop avoidance(BLA)处理，active 路径由 BLA 选择。显式"有线优先"还没做：早期试过用 watchdog 在有线在线时把无线从 batman 摘掉，但会导致下游无线 AP 重启后无法重新入网的死锁(典型商用 mesh 通病)，已移除。正路是把有线口也做成 batman hardif 并给无线设 `hop_penalty`，让 batman 原生偏好有线，列为后续工作。

## 当前限制

v0.1 还是脚手架，重点是先把 AC/AP 架构跑通：

- 配对控制目前是家庭网络用的简单模式：`Allow pairing` 开启时允许新 AP 注册，关闭后只保留已知 AP
- AC 自动发现已用 mDNS 实现，AP 也可手动固定 `ac_url`
- 有线和无线回程同时挂 batman-adv，环路靠 BLA；显式"有线优先"待后续用 batman hardif + hop_penalty 实现
- LuCI 页面目前只做基础配置、AP 在线/最后上报时间、AC 本机 Mesh 应用
- 还没有拓扑图、链路质量、在线状态详情
- 需要真机验证 IPQ60XX / MT7981 上的 802.11s、DAWN 和 KVR 组合

## 目录

```text
configs/                 OpenWrt 构建配置
package/mesh-ac/         AC 服务
package/mesh-agent/      AP agent
package/luci-app-mesh-ac LuCI 管理页面
scripts/                 构建准备脚本
.github/workflows/       GitHub Actions 编译流程
docs/                    设计说明
```

## 状态

当前仓库是第一版 MVP。下一步优先事项：

1. 跑完整 AC/AP 固件编译
2. 跑 MT7981 config-only workflow 并做真机验证
3. 两台 IPQ60XX 真机做有线配对测试
4. 验证 AC 本地 Mesh 成员模式
5. 验证拔线后的无线回程
6. 加入 wired-first / wireless-fallback watchdog
