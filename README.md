# OpenWrt Mesh AC

一个基于 OpenWrt / ImmortalWrt 的 Mesh AC + AP 管理项目，当前支持 IPQ60XX 和 MT7981。

当前目标不是一次性做完整商用 Mesh 系统，而是先做一个可编译、可配对、可下发配置的 MVP：

- AC 负责管理配置、显示 AP、批准配对、下发参数
- AP 刷入托管固件后自动向 AC 注册
- 第一次建议通过有线连接完成配对
- 配对后 AP 保存配置，即使 AC 暂时离线也继续工作
- 有线回程优先，无线 802.11s 回程作为兜底
- Wi-Fi 漫游使用 OpenWrt 的 `wpad` + 802.11k/v/r，客户端状态/漫游引导复用 DAWN
- AC 如果本身带 Wi-Fi，也可以作为本地 Mesh 成员加入同一套 SSID/回程

## 架构

```text
主路由 / AC
    |
    | 有线 LAN，首次配对和优先回程
    |
托管 AP 1  )) 802.11s wireless backhaul ))  托管 AP 2
    |
客户端 Wi-Fi SSID
```

AC 可以是负责拨号和 DHCP 的主路由，也可以只是挂在现有主路由下面的一个 OpenWrt 设备。AP 不默认负责拨号、DHCP 或 NAT。

如果 AC 自己也带 Wi-Fi，AC 固件默认提供本机 Mesh 成员模式。这个模式只应用 Wi-Fi AP、802.11s 回程、`batman-adv` 和 DAWN，不会把 AC 的 LAN/WAN/DHCP/防火墙改成托管 AP 模式。

## 组件

### `mesh-ac`

运行在 AC 设备上：

- 保存全局 Mesh 配置
- 接收 AP 注册
- 维护 AP 列表
- 批准 AP 配对
- 通过 CGI API 下发 AP 配置
- 可把 AC 本机 Wi-Fi 应用为本地 Mesh 成员

### `luci-app-mesh-ac`

AC 的 LuCI 管理页面：

- 配置客户端 SSID / 密码
- 配置无线回程 `mesh_id` / `mesh_key`
- 配置 802.11k/v/r
- 配置 DAWN 开关
- 查看和批准 AP
- 启用 AC 本地 Mesh 成员模式
- 手动应用 AC 本机 Wi-Fi / Mesh 配置

页面路径：

```text
Services -> Mesh AC
```

### `mesh-agent`

运行在 AP 设备上：

- 启动后向 AC 注册
- 等待 AC 批准
- 拉取 AC 下发的配置
- 写入 OpenWrt UCI 配置
- 生成 AP SSID、802.11s 回程、batman-adv、DAWN 参数
- 在 AC 本地成员模式下可用 `--preserve-lan` 只应用无线和 Mesh，不改 LAN/WAN/DHCP

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

`make defconfig` 后 workflow 会运行 `scripts/check-openwrt-config.sh`，主动检查以下关键内容：

- 目标设备 profile 是否存在
- IPQ：`kmod-ath11k-ahb` / `kmod-ath11k-pci`、IPQ6018 firmware、各设备 `ipq-wifi-*` BDF 包
- MTK：`kmod-mt7915e`、`kmod-mt7981-firmware`、`mt7981-wo-firmware`
- `wpad-openssl`
- `batman-adv` / `batctl`
- DAWN / uMDNS
- LuCI AC 应用和自研 `mesh-ac` / `mesh-agent`

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

workflow 会发布：

- 生成后的 `.config`
- 固件产物
- manifest / buildinfo / sha256sums

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
Pairing token
Client SSID
Client password
Mesh ID
Mesh key
Country
5 GHz channel
```

如果这台 AC 本身也要发 Wi-Fi / 加入 Mesh，保持 `Enable AC local mesh member` 开启，然后点击 `Apply local mesh config`。该动作会保留 AC 原有 LAN/WAN/DHCP/防火墙，只写入本机无线、802.11s、`batman-adv` 和 DAWN 配置。

### 2. 刷 AP 固件

其他节点刷入对应平台的 AP 固件：

```text
IPQ60XX-MESH-AP
MT7981-MESH-AP
```

AP 默认会访问：

```text
http://192.168.50.1/cgi-bin/mesh-ac
```

如果 AC 不是这个地址，需要在 AP 上修改：

```sh
uci set mesh_agent.main.ac_url='http://AC_IP/cgi-bin/mesh-ac'
uci set mesh_agent.main.pairing_token='你的配对 token'
uci commit mesh_agent
/etc/init.d/mesh-agent restart
```

### 3. 有线配对

把 AP 用网线接入 AC 所在 LAN。

AP 会自动注册。AC 页面会出现待批准 AP，点击 `Approve`。

批准后 AP 会拉取配置并应用：

- 客户端 Wi-Fi SSID
- 802.11k/v/r
- 802.11s 无线回程
- batman-adv
- DAWN

### 4. 无线回程

AP 配对成功后，可以拔掉网线。

AP 会保留无线 802.11s 回程配置，后续可通过无线回到 Mesh 网络。

再次插入网线时，设计目标是优先使用有线回程。当前 v0.1 已生成基础配置，后续会加入 watchdog 明确执行链路切换策略。

## 当前限制

v0.1 还是脚手架，重点是先把 AC/AP 架构跑通：

- 配对安全目前是共享 token，后续应改成配对窗口和每 AP 独立凭据
- AC 自动发现还未完成，AP 默认使用固定 `ac_url`
- 有线优先 / 无线兜底的 watchdog 还未完成
- LuCI 页面目前只做基础配置、批准 AP、AC 本机 Mesh 应用
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
