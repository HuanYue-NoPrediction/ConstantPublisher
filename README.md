# Constant Publisher

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
| 无法自动化 | 引擎层(steamcmd + VDF)与 UI 解耦,后续可加 CLI |

## 架构(致敬 FlClash 的分层)

```
UI(Flutter / Material 3, lib/ui)
  └── AppState(provider, lib/state)
        ├── mod_store:扫描 mods 目录,解析 modinfo.lua,读写 dstpub.json
        ├── stager:忽略规则 → 干净暂存副本(dry-run 即预览此清单)
        ├── steamcmd:生成 VDF → 调 steamcmd +workshop_build_item → 流式日志/进度
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
   flutter create . --platforms=windows --project-name constant_publisher
   flutter pub get
   ```
3. **运行**:
   ```powershell
   flutter run -d windows          # 调试运行
   flutter build windows           # 发布构建,产物在 build\windows\x64\runner\Release
   ```
4. **配置 steamcmd**(发布必需):
   - 从 <https://developer.valvesoftware.com/wiki/SteamCMD> 下载,解压到如 `E:\SteamCMD`;
   - 终端里跑一次 `steamcmd +login 你的账号`,输入密码和 Steam Guard 验证码(**只需一次**,凭据缓存在本机);
   - 应用「设置」页填 steamcmd 路径与账号。
5. **选 mods 目录**:「模组」页右下角,指向如 `...\steamapps\common\Don't Starve Together\mods`。

## 关键约定

- **`dstpub.json`**(每个模组文件夹一份,建议进 git):存 `publishedfileid`、上次发布版本、appid(DST=322330,DS=219740)、可见性、标签、附加忽略规则。
- **`.modignore`**(可选):每行一条 glob,`#` 注释;默认已忽略 `.git`、`exported/`、`*.psd`、`*.zip` 等。
- **首次发布**:留空 id → steamcmd `CreateItem` 后把新 id 写回 VDF,应用读回并存入 `dstpub.json`。
- **新文件夹更新老条目**:工坊页「手动绑定/换绑」,输入条目 id、选文件夹即可;旧文件夹的绑定自动解除。

## 已知限制(v0.1)

- 标签走 steamcmd 在老版本上不可靠(2024-10 后支持 kvtags),必要时上传后在工坊网页补;后续可换 Steamworks SDK 原生路径(steamworks.js / Steamworks.NET 同理的 Dart FFI)。
- Steam Guard 首次验证需在终端手动完成一次。
- 「从 Steam 拉取名下条目」需要 Web API Key + SteamID64(设置页,可选)。
- 尚未集成 ktech/autocompiler 的发布前重编译(计划为发布前检查项)。

## 许可

计划以 GPL-3.0 开源(界面布局致敬 FlClash 的 Material You 设计,代码全部原创)。
非 Klei / Valve 官方软件;Don't Starve 是 Klei Entertainment 商标,Steam 是 Valve 商标。
