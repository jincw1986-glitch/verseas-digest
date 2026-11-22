# 海外资讯简报

个人用的 iOS 阅读应用，加上这个公开仓库里的每日数据。装到手机上后，主屏幕显示的名字是「猫头鹰」。应用用简体中文阅读一份海外新闻摘要：先看当天这一期的图文版面，也可以翻以往各期。不打算上架公开 App Store，用自己的 Apple 开发者账号在 Xcode 里装到 iPhone，或走 TestFlight 内部测试。

应用不依赖第三方库。最低系统是 iOS 17。

本仓库是在没有 Xcode 的环境里写的，**没有在 Mac 上实际编译**。请在自己的 Mac 上打开工程，确认能编过再装到手机。

## 仓库里有什么

- `data/`：每日简报。应用从 GitHub 的 raw 地址读取这里的文件，安装包里也会带上一份，方便第一次打开和离线阅读。
- `OverseasDigest/`：SwiftUI 源码。
- `OverseasDigest.xcodeproj`：Xcode 工程。
- `scripts/validate.py`：检查数据是否符合约定。
- `.github/workflows/validate-data.yml`：每次 push 和 pull request 都会跑上面的脚本。

线上地址写在 `OverseasDigest/Config.swift` 的 `DigestConfig.baseURL`，目前是：

`https://raw.githubusercontent.com/jincw1986-glitch/verseas-digest/main/data`

只有这一处。换仓库或换分支时改这里即可。

## 数据格式

`data/schema.json` 是契约，`scripts/validate.py` 按它做检查，并额外要求句子数量、日期顺序和本地图片真实存在。

`data/index.json` 列出已发布的期数，**日期从新到旧**：

```json
{
  "issues": [
    {
      "date": "2026-11-21",
      "title": "2026年11月21日 · 海外资讯简报",
      "path": "issues/2026-11-21.json"
    }
  ]
}
```

每一期是 `data/issues/YYYY-MM-DD.json`。`date` 必须和文件名一致。从现在起，除「维基漫游」外，`sections` 必须按下面的顺序各出现一次，不能缺、不能换序。社会栏叫「社会与荒诞」，写社会事件，也写世界各地真实发生的荒诞事。「维基漫游」可以整栏不写；写了的话，必须紧挨在「笑话」之前。应用里如果这一期没有该栏，侧栏不会显示它。

已经写好的旧期不必改。文件里如果社会栏仍叫「社会资讯」，并且「天涯海角」排在「美女与野兽」前面，就按当时的旧顺序校验。

1. 每日一图
2. 国际政治与时事
3. 经济与市场
4. 科技与人工智能
5. 社会与荒诞
6. 科学与体育
7. 影视与明星
8. 书籍与作家
9. 美女与野兽
10. 天涯海角
11. 维基漫游（可省略）
12. 笑话

新闻栏目大约 5 则，允许 4 到 7 则。国际政治、经济、科技、社会、科学、影视、书籍都用下面的新闻格式。每一则新闻都必须有图。中国艺人只在新闻发生在海外、或和海外放映获奖有关时才放进来。每则新闻：

| 字段 | 要求 |
| --- | --- |
| `headline` | 标题 |
| `importance` | 建议为新一期的每条新闻填写。`major` 重大（影响广泛、后果深远或在该领域有里程碑意义），`notable` 重点（有明确影响或值得持续关注），`routine` 常规。旧数据可省略，概览会显示未评级。 |
| `summary` | 1 到 2 句摘要 |
| `sources` | 至少一条 `{ "name", "url" }`，`url` 必须是 `https://` |
| `image` | 必填。`path` 或 `url` 至少填一个，并写 `credit` |
| `glossary` | 1 到 3 条名词解释 |

名词解释：

| 字段 | 要求 |
| --- | --- |
| `term` | 词条，同一则里不要重复 |
| `type` | `person` 人物、`term` 术语或专名、`concept` 概念、`award` 奖项、`org` 机构 |
| `explanation` | 2 到 4 句，写核对过的事实，不要编 |

「每日一图」每天只有一张，用 `photo` 而不是 `items`。字段是 `title`、至少三段的 `interpretation`、`image` 和 `sources`。选当天最美、最有冲击力或最值得留下来的一张，写清拍摄者或制作者。

「天涯海角」每天只介绍一个地方，用 `place`。`paragraphs` 至少三段，写成有当地性格的散文，不要旅游宣传腔。`photos` 一到三张，每张都要有署名。

「美女与野兽」是图集，用 `gallery`。每张有 `kind`（`person` 或 `animal`）、短 `caption` 和 `image`。这里的美女指年轻、貌美的女性，可以是演员、模特、运动员等，用真实的公开活动、红毯或编辑照片，得体、不裸露，并写明署名。不要用年长者充数，也不要用生成图。动物同样要真实照片和署名。人物和动物都要有。

「维基漫游」每天介绍一篇真实的维基百科条目，用 `wiki` 而不是 `items`。可以不写这一栏。

| 字段 | 要求 |
| --- | --- |
| `title` | 简体中文标题 |
| `originalTitle` | 原文标题 |
| `tagline` | 一句话 |
| `body` | 300 到 500 个汉字，可以分段 |
| `images` | 1 到 2 张 `{ "url", "credit" }`，`url` 必须是 `https://` 的真实图片 |
| `sourceUrl` | 维基百科条目的 `https://` 链接 |

「段子」在 JSON 中使用栏目名「笑话」。每期至少 10 条，必须是 X 上真实存在的帖子，链接形如 `https://x.com/<handle>/status/<id>`，不能编造。内容保持得体。

| 字段 | 要求 |
| --- | --- |
| `text` | 帖子原文，保留原来的语言 |
| `translation` | 原文不是中文时必填 |
| `authorName` | 显示名 |
| `handle` | 以 `@` 开头，须与链接里的用户名一致 |
| `url` | 帖子地址 |
| `note` | 可省略。一句短注，解释笑点 |

图片若用 `path`，路径相对 `data/`，例如 `images/2026-11-21/voyager-1.jpg`，文件必须已经在仓库里。新闻条目从现在起必须配图：官方照片、新闻照片、书封，或维基共享资源等可以署名转载的真实照片。不要放 AI 生成图。画面如果不是当事人或事发地，署名里要写清楚拍的是什么，不要把风景说成新闻现场。当前这一期的旅行者1号图，是 NASA 2026年11月19日新闻稿里的艺术家概念图（公有领域），缩小后放进仓库，署名在 JSON 的 `credit` 里。应用读图时先看本机缓存，再看安装包里的 `data/`，最后才按仓库地址下载。某一张失败时，卡片上会留下该栏目颜色的占位，而不是空白。

## 怎样加一天

1. 新建 `data/issues/YYYY-MM-DD.json`，栏目按上面的顺序写完。
2. 把新闻、每日一图、地方和画廊的图片放到 `data/images/YYYY-MM-DD/`，在对应条目里用 `path` 指向它，并写 `credit`。也可以只填一个 `https` 图片地址。新闻条目不能省掉 `image`。
3. 打开 `data/index.json`，把这一天插到 `issues` 数组的**最前面**。`path` 写成 `issues/YYYY-MM-DD.json`。
4. 在仓库根目录运行：

   ```bash
   python3 scripts/validate.py
   ```

   只使用 Python 标准库，不需要安装别的包。通过时会打印「校验通过」。
5. 提交并推送。GitHub Action 会再查一次。推到 `main` 之后，手机上的应用下拉刷新就能读到新的一天。

改过图片或想让安装包里的离线副本一起更新时，需要重新用 Xcode 编译安装。只改文字的话，应用下次联网刷新就会拿到新 JSON，不必重装。

## 用 Mac 数据线装到 iPhone 17 Pro Max

这一路用你已经付费的 Apple Developer Program 账号，把应用直接装进那台 iPhone 17 Pro Max。不经过 TestFlight。

准备：一台 Mac；从 Mac App Store 安装 Xcode 15 或更新版本；一根能传输数据的 USB-C 线；手机已登录、屏幕已解锁。

1. 在 iPhone 17 Pro Max 上打开「设置 → 隐私与安全性 → 开发者模式」，打开开关。手机会要求重启。重启后再次确认开发者模式已开启。
2. 用数据线把这台 iPhone 17 Pro Max 接到 Mac。若手机弹出「要信任此电脑吗」，点「信任」，并输入手机锁屏密码。
3. 在 Mac 上克隆本仓库，双击根目录的 `OverseasDigest.xcodeproj`。
4. 菜单 Xcode → Settings → Accounts，用付费开发者账号的 Apple ID 登录。登录后应能看到你的付费团队，而不是只有 Personal Team。
5. 左侧点蓝色工程图标，选中 target **OverseasDigest**，打开 **Signing & Capabilities**。
6. 勾上 Automatically manage signing。Team 选那个付费团队。Bundle Identifier 保持 `com.jincw.overseasdigest`。如果提示已被别人占用，改成只属于你的一串，例如 `com.你的名字.overseasdigest`。后面 TestFlight 必须用同一个。
7. Xcode 窗口顶部的运行目标不要选模拟器。在设备列表里点你的 **iPhone 17 Pro Max**。
8. 按运行按钮（▶），或菜单 Product → Run。第一次编译会久一点。
9. 装好后若打不开，并提示不受信任的开发者：在手机上打开「设置 → 通用 → VPN 与设备管理」，点你的开发者证书，再点信任。然后回到主屏幕打开「猫头鹰」。

付费账号的描述文件按年更新。只要团队和 Bundle ID 不变，以后改完代码再按一次运行即可。

应用有三个页签：

- **今日**：启动时显示最新一期的概览。点顶部「每日一图」的图片或标题阅读故事。各新闻栏目以色条和条数显示重大、重点、常规的新闻分布。栏目按重大新闻条数排序，其次按重点新闻条数排序。点栏目进入卡片，点标题跳到对应新闻。点概览顶部「猫头鹰」可打开左侧栏目目录，选中栏目后直接进入阅读页。「每日一图」在概览顶部。栏里的每一则是一张接近全屏的卡片，左右滑动翻页，底部有页码点。卡片上方是通栏大图，标题压在渐变上；摘要、来源和蓝色「名词解释」在图下方，文字太长时只在这一张卡片里滚动。点图片可以全屏查看，双指缩放，下拉关闭，下面有署名。图片若没载入，卡片上会写「轻点重试」，不会留白。人物肖像和「美女与野兽」整张显示在模糊背景上，其他大图会躲开人脸再裁切。有「维基漫游」时，侧栏多出这一栏，样子和其他栏目一样。点图片可全屏查看，卡片上有「阅读维基原文」。「段子」包含原文、译文和作者链接，用暖色版式。来源在 App 内的 Safari 视图里打开。
- **往期**：可按日期查看每一期，也可按栏目筛选收录过该栏目的所有期数。按栏目筛选时，点日期可直接打开这一期的对应栏目。旧期的「社会资讯」归入「社会与荒诞」。
- **设置**：可打开每天当地时间 8:00 的本机提醒，通知正文是「今天的海外资讯简报已更新」。这是手机自己定时，不需要服务器推送。系统若拒绝通知，设置页会给出前往系统设置的按钮。也可以导出备份：把各期文字和图片打成一个 zip，存到文件或 iCloud 云盘；再从 zip 导入。导入会和手机上已有的期数合并，不重复添加。图片保存在本机的应用支持目录里，读取时优先用这份副本。

下拉可以刷新。成功读过的期数保存在手机上，没有网络时仍能打开。界面跟随系统深色模式，文字跟随系统字体大小（Dynamic Type）。

## 没有 Mac：用 GitHub Actions 上传到 TestFlight

电脑上不必安装 Xcode。仓库里的 `.github/workflows/testflight.yml` 会在 GitHub 的 macOS 虚拟机上编译、签名，并上传到 App Store Connect。你只在浏览器里准备账号、密钥和描述文件。工程已把 `ITSAppUsesNonExemptEncryption` 设为 NO，一般不用再填出口合规问卷。

先在浏览器里建好 App，否则上传没有地方可去。

1. 打开 [Apple Developer](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → 加号。选 App IDs → App，Bundle ID 选 Explicit，填 `com.jincw.overseasdigest`。若你改过工程里的 Bundle ID，这里必须改成同一个。
2. 打开 [App Store Connect](https://appstoreconnect.apple.com/apps) → 加号 → 新建 App。平台 iOS，名称可用「猫头鹰」，套装 ID 选上一步的 Bundle ID，SKU 自己起一个不重复的字符串。不必填上架截图，也不必提交审核。

然后在本仓库准备 7 个 Actions 密钥。打开 GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret。名称必须和下面左列完全一致，值不要加引号。

| 密钥名 | 填什么 | 从哪里拿到 |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10 位团队 ID | [Membership](https://developer.apple.com/account) 页面的 Team ID |
| `APP_STORE_CONNECT_KEY_ID` | API 密钥的 Key ID，约 10 位 | App Store Connect → 用户和访问 → 集成 → App Store Connect API → 团队密钥。生成时角色选 Admin 或 App Manager，页面上的 Key ID 就是它 |
| `APP_STORE_CONNECT_ISSUER_ID` | 签发者 UUID | 同一个 API 页面顶部的 Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `AuthKey_密钥ID.p8` 文件的 Base64 | 生成密钥时只能下载一次 `.p8`。在能跑命令的电脑上执行 `base64 -w 0 AuthKey_XXXX.p8`（macOS 用 `base64 -i AuthKey_XXXX.p8`），把整行输出贴进密钥 |
| `IOS_DISTRIBUTION_P12_BASE64` | 苹果分发证书 `.p12` 的 Base64 | 见下面「没有 Mac 怎么做出 p12」 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | 导出 p12 时你自己设的密码 | 就是你在 openssl 命令里输入的那串密码，原文保存 |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store 描述文件 `.mobileprovision` 的 Base64 | [Profiles](https://developer.apple.com/account/resources/profiles/list) → 加号 → App Store Connect → 选 `com.jincw.overseasdigest` 和上面的分发证书 → 下载。再执行 `base64 -w 0 那个文件.mobileprovision`。如果这条命令不认识 `-w`，改成 `base64 那个文件.mobileprovision | tr -d '\n'` |

没有 Mac 时，用 OpenSSL 做分发证书（Windows 的 Git Bash、Linux 或任何装了 OpenSSL 的电脑都可以）：

1. 生成私钥和证书请求：

   ```bash
   openssl req -nodes -newkey rsa:2048 -keyout ios_distribution.key -out ios_distribution.csr -subj "/CN=Overseas Digest Distribution"
   ```

2. 打开 [Certificates](https://developer.apple.com/account/resources/certificates/list) → 加号 → Apple Distribution。上传刚生成的 `ios_distribution.csr`，下载得到的 `.cer`。
3. 合成 p12。下载下来的 `.cer` 多半是 DER。密码自己定，记下来放进 `IOS_DISTRIBUTION_P12_PASSWORD`：

   ```bash
   openssl x509 -in distribution.cer -inform DER -out distribution.pem
   openssl pkcs12 -export -inkey ios_distribution.key -in distribution.pem -out distribution.p12
   base64 -w 0 distribution.p12
   ```

   如果 `openssl x509` 报格式错误，把 `-inform DER` 改成 `-inform PEM` 再试一次。`ios_distribution.key` 只留在你自己的电脑上，不要提交进仓库。

描述文件和证书必须是同一套：描述文件里选中的证书，就是这个 p12。

上传：

1. 确认上面 7 个密钥都已保存。
2. 打开本仓库的 Actions → **Upload TestFlight** → Run workflow → 选 `main`（合并之后）或当前分支 → Run。
3. 等这个 macOS 作业变绿。App Store Connect 里的构建版本还要再处理一段时间，处理中时 TestFlight 里看不到。
4. 在 iPhone 17 Pro Max 上安装苹果的 TestFlight App，用同一个 Apple ID 登录。
5. 打开 [该 App 的 TestFlight 页](https://appstoreconnect.apple.com)。你的账号若是 Admin、Developer 或 Marketing，内部测试组里就能看到这一版，不必做 Beta 审核。
6. 在 TestFlight 里点安装「猫头鹰」。

内部测试最多 100 人。外部测试要另做 Beta 审核，这个个人用途不用。

有 Mac 时仍可以走 Xcode 的 Product → Archive → Distribute App → App Store Connect。没有 Mac 时只用上面的工作流。

## 许可与内容

新闻摘要是根据公开报道另写的简短中文，不是原文摘抄。阅读细节请点来源。名词解释同样是背景说明，不是通讯社原稿。图片只应使用可以合理放进这个个人仓库的官方或新闻图片，并保留署名。
