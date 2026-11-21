# 海外资讯简报

个人用的 iOS 阅读应用，加上这个公开仓库里的每日数据。应用用简体中文阅读一份海外新闻摘要：先看当天这一期的图文版面，也可以翻以往各期。不打算上架公开 App Store，用自己的 Apple 开发者账号在 Xcode 里装到 iPhone，或走 TestFlight 内部测试。

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

每一期是 `data/issues/YYYY-MM-DD.json`。`date` 必须和文件名一致。`sections` 必须按下面的顺序各出现一次，不能缺、不能换序：

1. 每日一图
2. 国际政治与时事
3. 经济与市场
4. 科技与人工智能
5. 社会资讯
6. 科学与体育
7. 影视与明星
8. 书籍与作家
9. 天涯海角
10. 美女与野兽
11. 笑话

新闻栏目大约 5 则，允许 4 到 7 则。国际政治、经济、科技、社会、科学、影视、书籍都用下面的新闻格式。影视与明星的每一则都要有图。中国艺人只在新闻发生在海外、或和海外放映获奖有关时才放进来。每则新闻：

| 字段 | 要求 |
| --- | --- |
| `headline` | 标题 |
| `summary` | 1 到 2 句摘要 |
| `sources` | 至少一条 `{ "name", "url" }`，`url` 必须是 `https://` |
| `image` | 可省略。若有，则 `path` 或 `url` 至少填一个，并写 `credit` |
| `glossary` | 1 到 3 条名词解释 |

名词解释：

| 字段 | 要求 |
| --- | --- |
| `term` | 词条，同一则里不要重复 |
| `type` | `person` 人物、`term` 术语或专名、`concept` 概念、`award` 奖项、`org` 机构 |
| `explanation` | 2 到 4 句，写核对过的事实，不要编 |

「每日一图」每天只有一张，用 `photo` 而不是 `items`。字段是 `title`、至少三段的 `interpretation`、`image` 和 `sources`。选当天最美、最有冲击力或最值得留下来的一张，写清拍摄者或制作者。

「天涯海角」每天只介绍一个地方，用 `place`。`paragraphs` 至少三段，写成有当地性格的散文，不要旅游宣传腔。`photos` 一到三张，每张都要有署名。

「美女与野兽」是图集，用 `gallery`。每张有 `kind`（`person` 或 `animal`）、短 `caption` 和 `image`。人物用公开活动、红毯或编辑照片，保持得体，不放裸露内容。人物和动物都要有。

「笑话」的条目不同。每期至少 10 条，必须是 X 上真实存在的帖子，链接形如 `https://x.com/<handle>/status/<id>`，不能编造。内容保持得体。

| 字段 | 要求 |
| --- | --- |
| `text` | 帖子原文，保留原来的语言 |
| `translation` | 原文不是中文时必填 |
| `authorName` | 显示名 |
| `handle` | 以 `@` 开头，须与链接里的用户名一致 |
| `url` | 帖子地址 |
| `note` | 可省略。一句短注，解释笑点 |

图片若用 `path`，路径相对 `data/`，例如 `images/2026-11-21/voyager-1.jpg`，文件必须已经在仓库里。只收真实的新闻图片、官方图片或书封，并写明署名。不要放 AI 生成图。当前这一期的旅行者1号图，是 NASA 2026年11月19日新闻稿里的艺术家概念图（公有领域），缩小后放进仓库，署名在 JSON 的 `credit` 里。

## 怎样加一天

1. 新建 `data/issues/YYYY-MM-DD.json`，五个栏目按上面的顺序写完。
2. 如果有图，放到 `data/images/YYYY-MM-DD/`，在对应条目里用 `path` 指向它，并写 `credit`。也可以只填一个 `https` 图片地址。
3. 打开 `data/index.json`，把这一天插到 `issues` 数组的**最前面**。`path` 写成 `issues/YYYY-MM-DD.json`。
4. 在仓库根目录运行：

   ```bash
   python3 scripts/validate.py
   ```

   只使用 Python 标准库，不需要安装别的包。通过时会打印「校验通过」。
5. 提交并推送。GitHub Action 会再查一次。推到 `main` 之后，手机上的应用下拉刷新就能读到新的一天。

改过图片或想让安装包里的离线副本一起更新时，需要重新用 Xcode 编译安装。只改文字的话，应用下次联网刷新就会拿到新 JSON，不必重装。

## 在 Mac 上打开并装到 iPhone

准备：一台 Mac，从 App Store 安装 Xcode 15 或更新版本（能编译 iOS 17）。iPhone 系统需为 iOS 17 或更高。用数据线连接，并在手机上点「信任」。

1. 把这个仓库克隆到 Mac。
2. 双击打开根目录的 `OverseasDigest.xcodeproj`。
3. 菜单 Xcode → Settings → Accounts，登录你的 Apple ID。
4. 左侧点工程，选中 target **OverseasDigest**，打开 **Signing & Capabilities**。
5. 勾上 Automatically manage signing。Team 选你自己的个人团队或公司团队。
6. Bundle Identifier 目前是 `com.jincw.overseasdigest`。如果提示已被占用，改成只有你在用的一串，例如 `com.你的名字.overseasdigest`。后面如果走 TestFlight，App Store Connect 里要填同一个。
7. 窗口顶部的运行目标选你的 iPhone，不要选模拟器，然后按运行（▶）。
8. 第一次用免费 Apple ID 安装时，手机可能提示开发者不受信任。打开 iPhone 的「设置 → 通用 → VPN 与设备管理」（有的系统写成「设备管理」），信任你的开发者证书，再回到主屏幕打开「海外简报」。
9. 免费个人账号的签名大约 7 天后失效，过期后用 Xcode 再运行一次即可。付费开发者账号的直接安装时间更长。

应用有三个页签：

- **今日**：最新一期。左上角菜单打开栏目目录，点某一栏就跳过去。有图的栏目会把图片放在前面。新闻有摘要、来源和可展开的「名词解释」。笑话、每日一图、一个地方的散文、人物与动物图集，各自用不同版式。来源在 App 内的 Safari 视图里打开。
- **往期**：按日期列出 `index.json` 里的每一期。
- **设置**：可打开每天当地时间 8:00 的本机提醒，通知正文是「今天的海外资讯简报已更新」。这是手机自己定时，不需要服务器推送。系统若拒绝通知，设置页会给出前往系统设置的按钮。

下拉可以刷新。成功读过的期数保存在手机上，没有网络时仍能打开。界面跟随系统深色模式，文字跟随系统字体大小（Dynamic Type）。

## TestFlight 内部测试

内部测试需要加入 **Apple Developer Program**（付费）。只靠免费 Apple ID 不能上传 TestFlight。

1. 用上面的步骤配好 Team 和 Bundle Identifier，并确认手机上直接运行是成功的。
2. 顶部运行目标可以选 Any iOS Device（arm64）。菜单 **Product → Archive**。
3. 归档完成后 Organizer 会打开。选中这条归档，点 **Distribute App**。
4. 选 **App Store Connect** → **Upload**，按提示传上去。工程里已经把 `ITSAppUsesNonExemptEncryption` 设为 NO（只用系统自带的 HTTPS，没有自己加的加密），一般不会每传一次都问出口合规。如果仍然问到，选不使用非豁免加密。
5. 打开 [App Store Connect](https://appstoreconnect.apple.com)，新建 App。平台选 iOS，名称可以用「海外简报」，Bundle ID 与 Xcode 里完全一致，SKU 自己起一个不会重复的即可。这一步是为了内部测试，不必填写公开上架用的截图和审核说明，也不必提交审核。
6. 等构建版本处理完（通常要等一会儿，处理中时 TestFlight 里还看不到）。
7. 进入该 App 的 **TestFlight**。内部测试组会包含你的 App Store Connect 用户。你自己的 Apple ID 若已是 Admin、Developer 或 Marketing，装好手机上的 TestFlight App 后就能看到这一版，内部测试不需要 Beta 审核。
8. 若要给同团队的其他人：在 App Store Connect 的「用户和访问」里加入他们，角色不要选成只能看账务的那种，然后他们用那个 Apple ID 登录 TestFlight 接受安装。内部测试最多 100 人。

外部测试要填 Beta 审核信息，这个个人用途不需要。

## 许可与内容

新闻摘要是根据公开报道另写的简短中文，不是原文摘抄。阅读细节请点来源。名词解释同样是背景说明，不是通讯社原稿。图片只应使用可以合理放进这个个人仓库的官方或新闻图片，并保留署名。
