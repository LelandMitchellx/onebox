# Sing-Box 三合一全能服务端一键部署脚本

基于官方最新 [sing-box](https://github.com/SagerNet/sing-box) 核心，专为 Debian / Ubuntu 小鸡打造的极致轻量、高隐蔽代理服务端一键脚本。

单次部署同时启动当今最主流的三大防封锁协议：**VLESS + Reality (XTLS-Vision)**、**Hysteria 2 (QUIC)**、**AnyTLS**，互不干扰，一次搞定全场景需求。

---

## ✨ 核心特性

- 🚀 **全自动极速安装**：自动适配系统架构（amd64 / arm64 等），实时获取 GitHub 官方最新稳定版二进制。
- 🛡️ **高隐蔽防探测**：所有协议默认统一分配 **10000 - 60000 随机高位端口**，避开全网端口扫描与主动探测。
- ⚡ **最强流控 XTLS-Vision**：VLESS + Reality 默认启用最新 `xtls-rprx-vision`，智能填充，消除 TLS-in-TLS 特征。
- 🌐 **免域名免证书负担**：
  - Reality 借用大厂正规证书（默认 `addons.mozilla.org`），天然免证书。
  - Hysteria 2 / AnyTLS 现场生成 10 年免维护高强度自签证书，开箱即用。
- 🚄 **系统级 TCP BBR 优化**：自动检查并开启 Linux 内核 TCP BBR 拥塞控制算法。
- 📋 **全客户端开箱即用**：自动生成单行分享链接、Clash.Meta (Mihomo) 配置、Sing-box 客户端 JSON Outbound。
- 🛠️ **专属快捷管理工具**：内置极简 `sb` 运维指令（查看配置、启停、重启、实时日志、一键彻底卸载）。

---

## 📊 三大协议支持对比

| 协议 | 传输层 | 默认端口策略 | 证书方案 | 核心优势与适用场景 |
| :--- | :---: | :---: | :---: | :--- |
| **VLESS + Reality** | TCP | 随机高位 (10000-60000) | 借用大厂真实证书 | **日常主力首选**：免域名证书，大厂真身挡枪，最稳抗封锁 |
| **Hysteria 2** | UDP | 随机高位 (10000-60000) | 10年免维护自签证书 | **速度吞吐之王**：魔改 QUIC + Brutal，晚高峰与恶劣丢包网络神级加速 |
| **AnyTLS** | TCP | 随机高位 (10000-60000) | 10年免维护自签证书 | **轻量防指纹新秀**：动态包长填充，连接多路复用，消除特征分析 |

---

## 🚀 快速开始

### 方式一：单行全自动安装（推荐）

以 `root` 用户登录 VPS。针对极简纯净系统（自动安装 `curl` 依赖并执行）：

```bash
apt update -y && apt install -y curl && bash <(curl -fsSL https://raw.githubusercontent.com/LelandMitchellx/onebox/main/install.sh)
```

若系统中已确认安装了 `curl`，亦可直接执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LelandMitchellx/onebox/main/install.sh)
```

---

### 方式二：分步下载与部署

下载脚本：

```bash
curl -fsSL -O https://raw.githubusercontent.com/LelandMitchellx/onebox/main/install.sh
```

赋予执行权限并运行：

```bash
chmod +x install.sh
sudo ./install.sh
```

---

## ⚙️ 环境变量自定义（高级玩法，可选）

脚本默认无需任何参数即可全自动配置。如需固定端口或指定伪装域名，可在命令前添加环境变量：

| 环境变量 | 说明 | 默认值 | 示例 |
| :--- | :--- | :--- | :--- |
| `PORT` | VLESS + Reality 的 TCP 监听端口 | 随机高位端口 | `PORT=443` |
| `HY2_PORT` | Hysteria 2 的 UDP 监听端口 | 随机高位端口 | `HY2_PORT=8443` |
| `ANYTLS_PORT` | AnyTLS 的 TCP 监听端口 | 随机高位端口 | `ANYTLS_PORT=9443` |
| `REALITY_SNI` | Reality 借用证书的伪装域名 | `addons.mozilla.org` | `REALITY_SNI=gateway.icloud.com` |
| `CUSTOM_SNI` | 自签证书所使用的伪装域名 | `bing.com` | `CUSTOM_SNI=www.microsoft.com` |
| `HY2_PASS` | Hysteria 2 认证密码 | 自动随机生成 | `HY2_PASS=MyStrongPass123` |
| `ANYTLS_PASS` | AnyTLS 认证密码 | 自动随机生成 | `ANYTLS_PASS=MyStrongPass123` |

**自定义参数示例**：
```bash
PORT=443 HY2_PORT=8443 REALITY_SNI=gateway.icloud.com bash install.sh
```

---

## 🛠️ 服务端运维管理工具 (`sb`)

安装完成后，系统已自动创建极简管理指令 `sb`：

```bash
sb info       # 查看所有节点的分享链接、UUID、密码、Clash/Sing-box 配置
sb status     # 查看当前 sing-box 服务运行状态
sb log        # 实时追踪运行日志 (按 Ctrl + C 退出)
sb restart    # 重启服务 (修改配置后生效)
sb start      # 启动服务
sb stop       # 停止服务
sb uninstall  # 一键彻底干净卸载（清理服务、程序及所有配置文件）
```

节点详细参数会永久保存在本地文件中，也可随时查看：
```bash
cat /etc/sing-box/client-info.txt
```

---

## 📱 客户端导入指引

### 1. 通用链接直接导入
脚本执行完毕后会直接输出以下 3 条分享链接，复制后在客户端选择“从剪贴板导入”：
- **VLESS Reality**: `vless://...`
- **Hysteria 2**: `hysteria2://...` (或部分客户端兼容的 `hy2://...`)
- **AnyTLS**: `anytls://...`

### 2. 支持客户端推荐
- **Windows**: v2rayN (v6+), Clash Verge Rev, Flclash, sing-box-windows
- **Android**: v2rayNG, Clash Meta for Android (CMFA), NekoBox, SFA (Sing-box for Android)
- **iOS / macOS**: Shadowrocket (小火箭), Surge, Loon, Stash, Sing-box (SFI)

---

## ⚠️ 常见问题与避坑指南 (FAQ)

### Q1: Hysteria 2 导入后连不上，测速无响应？
**A**: **99% 的原因是因为云厂商控制台防火墙未放行 UDP 端口！**
请务必前往云服务器后台（如甲骨文、阿里云、腾讯云、AWS、Lightsail 等）的安全组/防火墙设置中，找到对应的 Hysteria 2 端口（如 `sb info` 中所示），**添加 UDP 入站允许规则**。

### Q2: 为什么 Hysteria 2 / AnyTLS 客户端需要允许“跳过证书校验 (insecure)”？
**A**: 因为这两个协议在没有绑定真实独立域名时，采用的是脚本现场生成的 ECC 高强度自签名证书。虽然没有商业机构颁发的证书签名，但底层通道传输加密强度与商业证书完全相同（AES/ChaCha20），防中间人篡改依靠的是生成的密码。

### Q3: 怎么修改配置？
**A**:
- 配置文件路径为：`/etc/sing-box/config.json`
- 修改后执行 `sb restart` 即可生效。
