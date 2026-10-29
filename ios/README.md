# wb2api iOS（自签 ipa）

把 `console` 网页控制台装进一个原生 WKWebView 外壳，用 GitHub Actions 的 macOS
机器编译出**无签名 ipa**，再用 Sideloadly / AltStore / TrollStore 自签安装。
不需要 Mac，不需要 Apple 开发者账号。

## 它是怎么工作的

```
iPhone ──► WB2API.app (SwiftUI + WKWebView)
              │  WKWebsiteDataStore.default()  ← 保留 admin cookie
              ▼
         https://你的服务器:7863/   ── Go console（docker compose / 桌面端）
              ├── /admin/login      管理密钥 → 会话 cookie + CSRF
              ├── /admin/*          账号、任务、对话测试
              └── /v1/*             OpenAI / Anthropic 兼容 API
```

iOS 沙盒不允许长期驻留后台服务进程，所以 App **不自带** Go 后端；它是指向你自己
服务器/电脑的瘦客户端。后端照旧用仓库根目录的 `docker-compose.yml` 或桌面端跑。

## 一、先在后端跑起来

```bash
# 服务器上
docker compose up -d
docker compose logs console | grep -i key    # 抄下管理密钥

# 本机验证
curl -s http://127.0.0.1:7863/livez
```

## 二、编译 ipa（GitHub Actions）

1. 把本仓库（含 `ios/` 与 `.github/workflows/ios-unsigned.yml`）推到自己的 fork / 私有仓库。
2. 打开 **Actions → iOS Unsigned IPA → Run workflow**。
   - `marketing_version` 留空则用工程里的 `0.1.0`；
   - `create_release` 勾上会把 ipa 放到一份 draft Release 里，方便下载。
3. 跑完约 3–5 分钟，在 run 页面底部 **Artifacts** 下载
   `wb2api-ios-unsigned-<版本>.ipa`。

产物说明：

| 文件 | 用途 |
| --- | --- |
| `wb2api-ios-unsigned-*.ipa` | Sideloadly / AltStore / ESign 自签安装 |
| `wb2api-ios-unsigned-*-app.zip` | TrollStore 直接拖入 `.app` |
| `*.ipa.sha256` | 校验下载完整性 |

## 三、自签安装

- **Sideloadly**（Windows/macOS）：拖入 ipa → 填自己 Apple ID → Start。
  免费账号签名 7 天有效期，到期重签即可。
- **AltStore / SideStore**：ipa 放进去，自动 7 天续签（需要一台常开的电脑或
  SideStore 的配对文件）。
- **TrollStore**（仅受支持的 iOS 版本）：装的是 `-app.zip` 解出来的 `.app`，
  永久签名，不会掉。
- **ESign / 轻松签**（纯手机）：导入 ipa + 证书，导出后安装。

## 四、首次启动

1. App 会直接弹出「首次配置」。
2. 服务器填 `https://你的域名` 或 `192.168.1.10:7863`（局域网）。
3. 管理密钥填第一步抄下来的那串。
4. 没有 TLS 证书的局域网机器，打开**允许明文 HTTP**。
5. 点「测试连接」，出现 `✓ 服务在线（/livez 200）` 就保存。

之后每次启动会自动带上密钥登录，地址栏里的 `admin_key` 会被注入脚本立即抹掉，
不会留在历史记录或截图里。密钥存在钥匙串（`kSecAttrAccessibleAfterFirstUnlock`），
不进 UserDefaults、不进 iCloud 备份的明文部分。

## 五、本地有 Mac 时

```bash
cd ios
xcodebuild -project WB2API.xcodeproj -scheme WB2API \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/WB2API.app Payload/
zip -qry wb2api.ipa Payload
```

有开发者账号要直接装到手机，把 `-sdk iphoneos` 目标换成
`-destination 'platform=iOS,id=<设备UDID>'`，并填 `DEVELOPMENT_TEAM`。

## 目录结构

```
ios/
├── WB2API.xcodeproj/           # 手写 pbxproj，勿手动改 UUID
│   └── xcshareddata/xcschemes/WB2API.xcscheme
├── WB2API/
│   ├── App/
│   │   ├── WB2APIApp.swift      # @main，前后台切换触发重载
│   │   ├── RootView.swift       # 未配置时的引导页 + 底部状态条
│   │   ├── ServerEditor.swift   # 地址/密钥表单、/livez 探活
│   │   ├── AppSettings.swift    # UserDefaults + Keychain
│   │   └── BrowserView.swift    # WKWebView 容器、UA、OAuth 跳转、弹窗桥
│   ├── Assets.xcassets/         # AppIcon 1024 + AccentColor
│   └── Info.plist               # ATS 例外、相机/相册/局域网用途说明
└── tools/make_icon.py           # 从 icon.svg 几何重绘 1024 图标
```

重新生成图标：

```bash
cd ios && python3 tools/make_icon.py WB2API/Assets.xcassets/AppIcon.appiconset
```

## 已知边界

- **签名有效期**：免费 Apple ID 7 天，付费账号 1 年，TrollStore 永久。
- **后台常驻**：iOS 不给你跑常驻 Go 进程，签到任务要去后端跑。
- **推送**：无签名包没有 APNs 证书，不做远程推送，靠 App 前台轮询。
- **Bundle ID**：`com.workbuddy2api.mobile`，改它需要同步改 `project.pbxproj`
  里的 `PRODUCT_BUNDLE_IDENTIFIER`，否则覆盖安装会变成两个 App。
