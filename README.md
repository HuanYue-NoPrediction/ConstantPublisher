# DST Mod Publisher

饥荒(Don't Starve / DST)Steam 创意工坊模组上传器 —— Material You 界面 + steamcmd 引擎。
用来替代官方 Mod Tools 里的 ModUploader,解决它的老毛病:

| 官方痛点 | 本工具的解法 |
|---|---|
| 整个文件夹无脑全传 | `.modignore` + 默认忽略规则,上传前可视化"将要上传"清单 |
| 上传失败清空全部已编辑数据 | 全表单草稿自动保存(按模组隔离),失败原样保留、直接重试 |
| 只有裸文本简介框 | BBCode 工具栏 + 实时预览 |
| 没有更新日志字段 | changenote 随每次更新写入 Steam「更新记录」 |
| 版本号手动改 modinfo.lua | 一键自增并写回,取"本地/工坊较高版本 +1" |
| 依赖 Steam 返回的列表(2020 年崩溃根因) | 真相源是每个模组文件夹里的 `dstpub.json`,可进版本库 |
| 换文件夹更新老条目很麻烦 | 工坊页手动绑定/换绑:任意条目 id ↔ 任意本地文件夹 |
| EResult 裸报数字 | 错误码自动翻译成人话(见 `lib/models/eresult.dart`) |
| 无法自动化 | 双引擎:Steamworks(桌面默认)+ steamcmd(CI/无头环境) |

## 最终用户怎么用(零配置)

解压发行包 → **确保 Steam 客户端开着、账号拥有饥荒** → 双击 `dst_mod_publisher.exe`。
没了。默认的 **Steamworks 引擎**(`helper/CpSteamHelper.exe`)借用已登录的 Steam
会话完成上传,与官方 ModUploader 同机制:不输账号、不输密码、不装 steamcmd。
标签通过 `SetItemTags` 可靠写入,上传进度来自 `GetItemUpdateProgress` 真实字节数。
提示:上传期间 Steam 可能显示"正在玩 Don't Starve Together",属正常现象(以游戏身份接入)。

## 架构(致敬 FlClash 的分层)

```
UI(Flutter / Material 3, lib/ui)
  └── AppState(provider, lib/state)
        ├── stager:忽略规则 → 干净暂存副本(dry-run 即预览此清单)
        ├── steamworks_engine:调 helper/CpSteamHelper.exe(C# + Steamworks.NET)
        │     └── 借用已登录 Steam 会话:CreateItem / SubmitItemUpdate / SetItemTags
        ├── steamcmd:生成 VDF → steamcmd +workshop_build_item(CI/无头环境备用)
        ├── draft_store:表单草稿(SharedPreferences,按模组路径隔离)
        └── workshop_api:可选,Steam Web API 拉取名下条目做巡检
```

## 从零跑起来(Windows)

1. **安装 Flutter SDK**(约 10 分钟):
   ```powershell
   winget install --id=Google.Flutter -e
   # 或从 https://docs.flutter.dev/get-started/install/windows 下载 zip 解压并加入 PATH
   flutter doctor          # 按提示装 Visual Studio 的 "Desktop development with C++" 工作负载
   ```
2. **生成 Windows 平台壳**(本仓库只含 Dart 源码,平台胶水由 Flutter 生成):
   ```powershell
   cd E:\ConstantPublisher
   flutter create . --platforms=windows --project-name dst_mod_publisher
   flutter pub get
   ```
3. **运行**:
   ```powershell
   flutter run -d windows          # 调试运行
   flutter build windows           # 发布构建,产物在 build\windows\x64\runner\Release
   ```
4. **构建 Steamworks 助手**(需 .NET 8 SDK,`winget install Microsoft.DotNet.SDK.8`):
   ```powershell
   dotnet publish helper/CpSteamHelper.csproj -c Release -o build\windows\x64\runner\Release\helper
   ```
   (CI 已自动做这一步;本地开发跑 `flutter run` 前手动执行一次即可)
5. **选 mods 目录**:「模组」页右下角,指向如 `...\steamapps\common\Don't Starve Together\mods`。
6. (可选,仅 steamcmd 引擎)从 <https://developer.valvesoftware.com/wiki/SteamCMD> 下载 steamcmd,
   终端跑一次 `steamcmd +login 你的账号` 过 Steam Guard,再到「设置」页填路径与账号。

## 关键约定

- **`dstpub.json`**(每个模组文件夹一份,建议进 git):存 `publishedfileid`、上次发布版本、appid(DST=322330,DS=219740)、可见性、标签、附加忽略规则。
- **`.modignore`**(可选):每行一条 glob,`#` 注释;默认已忽略 `.git`、`exported/`、`*.psd`、`*.zip` 等。
- **首次发布**:留空 id → steamcmd `CreateItem` 后把新 id 写回 VDF,应用读回并存入 `dstpub.json`。
- **新文件夹更新老条目**:工坊页「手动绑定/换绑」,输入条目 id、选文件夹即可;旧文件夹的绑定自动解除。

## 已知限制(v0.2)

- Steamworks 引擎要求账号**拥有目标游戏**(DST=322330 / DS=219740),且 Steam 客户端在运行。
- steamcmd 引擎(备用)仍需终端过一次 Steam Guard;其标签写入在老版 steamcmd 上不可靠。
- 「从 Steam 拉取名下条目」需要 Web API Key + SteamID64(设置页,可选)。
- 尚未集成 ktech/autocompiler 的发布前重编译(计划为发布前检查项)。

## 许可

计划以 GPL-3.0 开源(界面布局致敬 FlClash 的 Material You 设计,代码全部原创)。
非 Klei / Valve 官方软件;Don't Starve 是 Klei Entertainment 商标,Steam 是 Valve 商标。
