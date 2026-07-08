# DST Mod Publisher · 饥荒模组发布器

饥荒(Don't Starve / DST)Steam 创意工坊模组发布工具 —— 开着 Steam 就能用,替代官方 Mod Tools 里的 ModUploader。

Material You 界面 · 多语言简介 · 选择性更新 · 自动更新 · GPL-3.0 开源

## 下载

- **创意工坊(推荐)**:[订阅工坊页面](https://steamcommunity.com/sharedfiles/filedetails/?id=3758340920),到 `steamapps/workshop/content/322330/3758340920/` 解压 zip 即可,以后 Steam 自动推送新版本;
- **GitHub**:[Releases](https://github.com/HuanYue-NoPrediction/ConstantPublisher/releases) 下载 `DSTModPublisher-windows.zip`。

解压后确保 Steam 客户端已登录,双击 `dst_mod_publisher.exe`。不输账号、不输密码、零依赖。
装一次即可:工具会自动检查并提示新版本,一键升级自动重启。

## 对照官方上传器

| 官方痛点 | 本工具 |
|---|---|
| 上传失败清空全部已编辑数据 | 全表单草稿自动保存,失败原样保留、直接重试 |
| 只想改简介也要整包重传 | **选择性更新**:勾选本次更新内容文件 / 标题简介 / 封面 / 标签 / 可见性 |
| 简介只有裸文本框、单语言 | **多语言**标题/简介分开编辑(简中/英/繁/日/韩/俄),BBCode 全标签工具栏 + 实时预览,自动拉取工坊各语言现状作底稿 |
| 整个文件夹无脑全传 | 默认忽略规则 + `.modignore` + 清单里**点击文件/文件夹切换上传或忽略**,选择记忆在 `dstpub.json` |
| 没有更新日志字段 | changenote 随每次更新写入 Steam「更新记录」 |
| 版本号手动改 modinfo.lua | 一键自增写回,自动维护工坊 `version:` 标签与 metadata,强制"必须大于线上版本" |
| 换文件夹/换机器更新老条目麻烦 | **目标与内容分离**:发布目标(工坊条目/新建)和内容文件夹各选各的;可见性、标签、简介均以工坊线上值为基线预设 |
| EResult 裸报数字 | 错误码自动翻译成人话并附建议 |
| 无法自动化 | 双引擎:Steamworks(桌面默认)+ steamcmd(CI/无头环境) |

此外:

- 发布时自动生成 **mod.manifest**(游戏资源索引,MNFS + SDBM 路径哈希),与官方上传器行为一致;
- 仪表盘:名下条目排行(封面/订阅/评论/好评率,全量 + 搜索)、**饥荒官方动态公告栏**、模组交流群;所有工坊链接优先在 Steam 客户端内打开;
- **自动更新双通道**:订阅工坊页由 Steam 推送(免下载),否则走 GitHub Release 文件直链(不受 API 限流影响);更新替换由随包的 helper 完成,无脚本、任意语言用户名可用;
- 深色模式默认,14 种主题色。

## 架构

```
UI(Flutter / Material 3, lib/ui)
  └── AppState(provider, lib/state)
        ├── stager:忽略规则 → 干净暂存副本 + 生成 mod.manifest
        ├── steamworks_engine:调 helper/CpSteamHelper.exe(C# + Steamworks.NET)
        │     └── 借已登录 Steam 会话,以 Mod Tools(245850)身份接入
        │         模式:publish(多语言/选择性更新)/ list / desc / delete / apply(自更新替换)
        ├── steamcmd:生成 VDF → steamcmd +workshop_build_item(CI/无头备用)
        ├── updater:双通道检查(工坊 version.txt / GitHub 直链)+ 下载进度 + helper 自替换
        ├── draft_store:表单草稿(按 内容文件夹 × 发布目标 隔离)
        └── workshop_api:Steam Web API 巡检(可选)+ ISteamNews 官方动态
```

## 从源码构建(Windows)

仓库只含 Dart/C# 源码,平台胶水由 Flutter 生成:

```powershell
flutter create . --platforms=windows --project-name dst_mod_publisher
flutter pub get
dart run flutter_launcher_icons
flutter build windows
dotnet publish helper/CpSteamHelper.csproj -c Release -o build\windows\x64\runner\Release\helper
```

需要 Flutter SDK(stable)、.NET 8 SDK、VS "Desktop development with C++" 工作负载。
CI(`.github/workflows/build.yml`)对每个 `v*` 标签自动构建 Windows/macOS 包并发布 Release。

## 关键约定

- **`dstpub.json`**(每个模组文件夹一份):appid、可见性、标签、`ignore`/`keep` 忽略与保留规则。不存工坊条目 id ——发布目标每次在发布页显式选择;
- **`.modignore`**(可选):每行一条 glob,`#` 注释;
- 工坊条目的版本号写入 UGC metadata 与 `version:` 标签(DST 社区惯例),更新前校验必须大于线上版本;
- modinfo.lua 兼容 GBK 编码与 `name = chinese and "中" or "En"` 双语写法。

## macOS(实验)

CI 产出未签名的 `DSTModPublisher-macos.zip`(Apple Silicon)。首次运行需
`xattr -dr com.apple.quarantine`。Steamworks 链路在 macOS 上尚待验证,欢迎反馈。

## 反馈与交流

- 作者:唤月(HuanYue)· 1713597367@qq.com
- [GitHub Issues](https://github.com/HuanYue-NoPrediction/ConstantPublisher/issues) · [创意工坊评论区](https://steamcommunity.com/sharedfiles/filedetails/?id=3758340920)
- QQ 群:饥荒MOD动画_Anim研究所 1018104063 · 饥荒mod制作-五年一班 620984175

## 许可与声明

[GPL-3.0](LICENSE)。界面布局致敬 [FlClash](https://github.com/chen08209/FlClash) 的 Material You 设计,代码全部原创。
本工具为社区作品,与 Klei Entertainment / Valve 无关;Don't Starve 是 Klei Entertainment 的商标,Steam 是 Valve 的商标。
上传期间 Steam 可能显示"正在玩 Don't Starve Together",属 Steamworks 接入的正常现象。
