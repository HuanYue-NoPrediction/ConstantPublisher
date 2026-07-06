using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using Steamworks;

// Constant Publisher 的 Steamworks 助手进程。
// 职责单一:读取 argv[0] 指向的请求 JSON,借用「正在运行且已登录」的
// Steam 客户端会话执行创意工坊发布,以 JSON 行协议向 stdout 汇报进度与结果。
// 全程不接触、不存储任何用户凭据 —— 身份来自 Steam 客户端本身。
internal static class Program
{
    private sealed record LangEntry(string Language, string Title, string Description);

    private sealed record Request(
        uint AppId,
        ulong PublishedFileId,
        string ContentFolder,
        string? PreviewFile,
        string Title,
        string Description,
        string ChangeNote,
        int Visibility,
        string[]? Tags,
        string? Version,
        LangEntry[]? Languages, // 多语言:每种语言各自的标题/简介;第一条带内容上传
        bool? UpdateContent,
        bool? UpdateText,
        bool? UpdatePreview,
        bool? UpdateTags,
        bool? UpdateVisibility);

    private static bool _createDone;
    private static bool _submitDone;
    private static bool _queryDone;
    private static bool _ioFailure;
    private static CreateItemResult_t _createResult;
    private static SubmitItemUpdateResult_t _submitResult;
    private static SteamUGCQueryCompleted_t _queryResult;

    // CallResult 必须在整个异步等待期间保持存活,否则 GC 回收后原生回调
    // 会访问已释放内存 → 0xC0000005 崩溃。提为静态字段以钉住其生命周期。
    private static CallResult<CreateItemResult_t>? _createCR;
    private static CallResult<SubmitItemUpdateResult_t>? _submitCR;
    private static CallResult<SteamUGCQueryCompleted_t>? _queryCR;

    // 以 "Don't Starve Mod Tools"(245850)的身份接入 Steam —— 官方 ModUploader 就是这样:
    // 它由 Steam 以此 app 启动,再对游戏(322330 等)建/更新工坊条目。
    // 直接以游戏 appid 初始化会被 Steam 拒绝(游戏不能自我发布),导致 CreateItem 回调永不返回。
    private const uint LaunchAppId = 245850;

    private static void Emit(object o) =>
        Console.WriteLine(JsonSerializer.Serialize(o));

    private static void Fail(string error, int eresult = 0) =>
        Emit(new { @event = "result", ok = false, error, eresult });

    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);

        // 模式四:desc <publishedfileid> —— 按各语言分别取该条目的标题/简介
        // (list 只取默认语言;多语言编辑需要每种语言各自的底稿)
        if (args.Length >= 2 && args[0] == "desc")
        {
            Environment.SetEnvironmentVariable("SteamAppId", LaunchAppId.ToString());
            Environment.SetEnvironmentVariable("SteamGameId", LaunchAppId.ToString());
            if (!TryInit(LaunchAppId)) return 0;
            try { return RunDesc(ulong.Parse(args[1])); }
            catch (Exception e) { Fail("取简介失败: " + e.Message); return 0; }
            finally { SteamAPI.Shutdown(); }
        }

        // 模式三:delete <publishedfileid> —— 删除工坊条目
        if (args.Length >= 2 && args[0] == "delete")
        {
            Environment.SetEnvironmentVariable("SteamAppId", LaunchAppId.ToString());
            Environment.SetEnvironmentVariable("SteamGameId", LaunchAppId.ToString());
            if (!TryInit(LaunchAppId)) return 0;
            try
            {
                var id = ulong.Parse(args[1]);
                SteamUGC.DeleteItem(new PublishedFileId_t(id));
                // DeleteItem 是异步的,但对我们只需发出即可;短暂 pump 让请求送达
                for (var k = 0; k < 20; k++) { SteamAPI.RunCallbacks(); Thread.Sleep(100); }
                Emit(new { @event = "result", ok = true, deleted = args[1] });
            }
            catch (Exception e) { Fail("删除失败: " + e.Message); }
            finally { SteamAPI.Shutdown(); }
            return 0;
        }

        // 模式二:list <appid> —— 借 Steam 会话列出当前账号名下的工坊条目,零配置
        if (args.Length >= 1 && args[0] == "list")
        {
            var listAppId = args.Length >= 2 && uint.TryParse(args[1], out var a) ? a : 322330u;
            // 以 Mod Tools 身份初始化,查询目标仍是游戏 appid
            Environment.SetEnvironmentVariable("SteamAppId", LaunchAppId.ToString());
            Environment.SetEnvironmentVariable("SteamGameId", LaunchAppId.ToString());
            if (!TryInit(LaunchAppId)) return 0;
            try
            {
                return RunList(new AppId_t(listAppId));
            }
            catch (Exception e)
            {
                Fail("助手内部异常: " + e.Message);
                return 0;
            }
            finally
            {
                SteamAPI.Shutdown();
            }
        }

        if (args.Length < 1 || !File.Exists(args[0]))
        {
            Fail("缺少请求文件参数");
            return 1;
        }

        Request req;
        try
        {
            req = JsonSerializer.Deserialize<Request>(
                File.ReadAllText(args[0]),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        }
        catch (Exception e)
        {
            Fail("请求 JSON 解析失败: " + e.Message);
            return 1;
        }

        // 以 Mod Tools(245850)身份接入 Steam;发布目标游戏见 req.AppId。
        // 必须在 Init 之前设置,替代 steam_appid.txt。
        Environment.SetEnvironmentVariable("SteamAppId", LaunchAppId.ToString());
        Environment.SetEnvironmentVariable("SteamGameId", LaunchAppId.ToString());

        if (!TryInit(LaunchAppId)) return 0;

        try
        {
            return Run(req);
        }
        catch (Exception e)
        {
            Fail("助手内部异常: " + e.Message);
            return 0;
        }
        finally
        {
            SteamAPI.Shutdown();
        }
    }

    private static int Run(Request req)
    {
        var appId = new AppId_t(req.AppId);
        var fileId = new PublishedFileId_t(req.PublishedFileId);

        if (req.PublishedFileId == 0)
        {
            Emit(new { @event = "stage", stage = "CreateItem · 新建工坊条目" });
            var call = SteamUGC.CreateItem(appId, EWorkshopFileType.k_EWorkshopFileTypeCommunity);
            if (call.m_SteamAPICall == 0)
            {
                Fail("CreateItem 被 Steam 拒绝 —— 确认 Steam 在线、账号拥有饥荒,且 helper 旁的 steam_api64.dll 与 Steamworks.NET 版本匹配", 0);
                return 0;
            }
            _createCR = CallResult<CreateItemResult_t>.Create(OnCreateItem);
            _createCR.Set(call);
            if (!Pump(() => _createDone, 60))
            {
                Fail("CreateItem 超时(60 秒)", 0);
                return 0;
            }
            if (_ioFailure || _createResult.m_eResult != EResult.k_EResultOK)
            {
                Fail("CreateItem 失败", (int)_createResult.m_eResult);
                return 0;
            }
            fileId = _createResult.m_nPublishedFileId;
            Emit(new { @event = "log", message = "已创建条目 id " + fileId.m_PublishedFileId });
            if (_createResult.m_bUserNeedsToAcceptWorkshopLegalAgreement)
            {
                Emit(new { @event = "log", message = "提示:需在 Steam 接受创意工坊法律协议后,条目才对他人可见" });
            }
        }

        var isNew = req.PublishedFileId == 0;
        var upContent = isNew || (req.UpdateContent ?? true);
        var upText = isNew || (req.UpdateText ?? true);
        var upPreview = isNew || (req.UpdatePreview ?? true);
        var upTags = isNew || (req.UpdateTags ?? true);
        var upVisibility = isNew || (req.UpdateVisibility ?? true);

        List<LangEntry> langs = upText && req.Languages != null && req.Languages.Length > 0
            ? new List<LangEntry>(req.Languages)
            : new List<LangEntry> { new("english", req.Title, req.Description) };

        for (var li = 0; li < langs.Count; li++)
        {
            var L = langs[li];
            var withContent = li == 0; // 只有首条上传内容,其余是纯元数据更新(快)
            Emit(new { @event = "stage", stage = withContent
                ? (upContent ? $"上传内容 · 语言 {L.Language}" : "更新条目元数据")
                : $"更新 {L.Language} 语言的标题/简介" });

            var h = SteamUGC.StartItemUpdate(appId, fileId);
            if (upText)
            {
                SteamUGC.SetItemUpdateLanguage(h, L.Language);
                SteamUGC.SetItemTitle(h, L.Title);
                SteamUGC.SetItemDescription(h, L.Description);
            }

            if (withContent)
            {
                if (upContent)
                    SteamUGC.SetItemContent(h, req.ContentFolder);
                if (upPreview && !string.IsNullOrEmpty(req.PreviewFile))
                    SteamUGC.SetItemPreview(h, req.PreviewFile);
                if (upVisibility)
                    SteamUGC.SetItemVisibility(h, (ERemoteStoragePublishedFileVisibility)req.Visibility);
                if (upContent || upTags)
                {
                    // 标签:SetItemTags 整体替换,把 version:<版本> 一并写入
                    var tagList = new List<string>();
                    if (req.Tags != null) tagList.AddRange(req.Tags);
                    tagList.RemoveAll(t => t.StartsWith("version:", StringComparison.OrdinalIgnoreCase));
                    if (!string.IsNullOrEmpty(req.Version)) tagList.Add("version:" + req.Version);
                    if (tagList.Count > 0 && !SteamUGC.SetItemTags(h, tagList))
                        Emit(new { @event = "log", message = "警告:SetItemTags 返回 false" });
                }
                if (upContent && !string.IsNullOrEmpty(req.Version))
                    SteamUGC.SetItemMetadata(h, req.Version);
            }

            _submitDone = false;
            var sub = SteamUGC.SubmitItemUpdate(h, req.ChangeNote);
            _submitCR = CallResult<SubmitItemUpdateResult_t>.Create(OnSubmit);
            _submitCR.Set(sub);

            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (!_submitDone)
            {
                SteamAPI.RunCallbacks();
                var status = SteamUGC.GetItemUpdateProgress(h, out ulong done, out ulong total);
                if (total > 0)
                    Emit(new { @event = "progress", status = status.ToString(), done, total });
                if (sw.Elapsed > TimeSpan.FromMinutes(30)) { Fail("上传超时(30 分钟)"); return 0; }
                Thread.Sleep(200);
            }

            if (_ioFailure || _submitResult.m_eResult != EResult.k_EResultOK)
            {
                var er = (int)_submitResult.m_eResult;
                var hint = er == 2
                    ? "(EResult 2 常见于 Steam 内容 CDN 网络问题:无法取回旧清单做增量,多为网络波动,稍后重试即可)"
                    : "";
                Fail($"SubmitItemUpdate 失败 · 语言 {L.Language} {hint}", er);
                return 0;
            }
        }

        Emit(new
        {
            @event = "result",
            ok = true,
            publishedFileId = fileId.m_PublishedFileId.ToString(),
            needsLegalAgreement = _submitResult.m_bUserNeedsToAcceptWorkshopLegalAgreement,
        });
        return 0;
    }

    // 按语言逐一查询单个条目的标题/简介。Steam 对没填某语言的项会回退到"默认语言",
    // 故按内容频次去重:出现多次的那份=默认语言(仅归给它的真正拥有者,优先 english),
    // 其余共享它的语言视为回退、跳过;只出现一次的才是该语言的真翻译。
    private static int RunDesc(ulong id)
    {
        var langs = new[] { "schinese", "english", "tchinese", "koreana", "japanese", "russian" };
        var results = new List<(string lang, string title, string desc)>();

        foreach (var lang in langs)
        {
            var q = SteamUGC.CreateQueryUGCDetailsRequest(
                new[] { new PublishedFileId_t(id) }, 1);
            if (q.m_UGCQueryHandle == ulong.MaxValue) continue;
            SteamUGC.SetLanguage(q, lang);
            SteamUGC.SetReturnLongDescription(q, true);
            _queryDone = false;
            _queryCR = CallResult<SteamUGCQueryCompleted_t>.Create(OnQuery);
            _queryCR.Set(SteamUGC.SendQueryUGCRequest(q));
            if (!Pump(() => _queryDone, 20)) { SteamUGC.ReleaseQueryUGCRequest(q); continue; }
            if (!_ioFailure && _queryResult.m_eResult == EResult.k_EResultOK &&
                _queryResult.m_unNumResultsReturned > 0 &&
                SteamUGC.GetQueryUGCResult(_queryResult.m_handle, 0, out SteamUGCDetails_t d))
            {
                results.Add((lang, d.m_rgchTitle ?? "", d.m_rgchDescription ?? ""));
            }
            SteamUGC.ReleaseQueryUGCRequest(q);
        }

        // 频次:出现 >1 次的 desc 是默认语言的回退;归属优先 english,否则该组第一个
        var freq = new Dictionary<string, int>();
        foreach (var r in results)
            freq[r.desc] = freq.TryGetValue(r.desc, out var c) ? c + 1 : 1;
        string? sharedDesc = null;
        var maxCount = 1;
        foreach (var kv in freq)
            if (kv.Value > maxCount) { maxCount = kv.Value; sharedDesc = kv.Key; }
        string? sharedOwner = null;
        if (sharedDesc != null)
        {
            var group = results.FindAll(r => r.desc == sharedDesc).ConvertAll(r => r.lang);
            sharedOwner = group.Contains("english") ? "english" : group[0];
        }

        foreach (var r in results)
        {
            if (r.desc == sharedDesc && r.lang != sharedOwner) continue; // 回退,跳过
            if (string.IsNullOrEmpty(r.desc) && string.IsNullOrEmpty(r.title)) continue;
            Emit(new { @event = "lang", lang = r.lang, title = r.title, desc = r.desc });
        }
        Emit(new { @event = "result", ok = true });
        return 0;
    }

    private static int RunList(AppId_t appId)
    {
        var account = SteamUser.GetSteamID().GetAccountID();
        uint page = 1;
        var total = 0;
        while (page <= 10)
        {
            // creator = Mod Tools(245850,即上传者身份),consumer = 目标游戏。
            // 以 245850 运行时,若 creator/consumer 都不是 245850(如都填 322330),
            // 或 creator=0,v017 的 dll 会返回无效查询句柄 → 回调永不返回。
            var q = SteamUGC.CreateQueryUserUGCRequest(
                account,
                EUserUGCList.k_EUserUGCList_Published,
                EUGCMatchingUGCType.k_EUGCMatchingUGCType_Items,
                EUserUGCListSortOrder.k_EUserUGCListSortOrder_LastUpdatedDesc,
                new AppId_t(LaunchAppId), appId, page);
            if (q.m_UGCQueryHandle == ulong.MaxValue) // k_UGCQueryHandleInvalid
            {
                Fail("CreateQueryUserUGCRequest 返回无效句柄");
                return 0;
            }
            SteamUGC.SetReturnMetadata(q, true);
            SteamUGC.SetReturnLongDescription(q, true);
            _queryDone = false;
            _queryCR = CallResult<SteamUGCQueryCompleted_t>.Create(OnQuery);
            _queryCR.Set(SteamUGC.SendQueryUGCRequest(q));
            if (!Pump(() => _queryDone, 30))
            {
                SteamUGC.ReleaseQueryUGCRequest(q);
                Fail("QueryUserUGC 超时(30 秒)");
                return 0;
            }
            if (_ioFailure || _queryResult.m_eResult != EResult.k_EResultOK)
            {
                SteamUGC.ReleaseQueryUGCRequest(q);
                Fail("QueryUserUGC 失败", (int)_queryResult.m_eResult);
                return 0;
            }
            var n = _queryResult.m_unNumResultsReturned;
            for (uint i = 0; i < n; i++)
            {
                if (!SteamUGC.GetQueryUGCResult(_queryResult.m_handle, i, out SteamUGCDetails_t d))
                {
                    continue;
                }
                ulong Stat(EItemStatistic s)
                {
                    SteamUGC.GetQueryUGCStatistic(
                        _queryResult.m_handle, i, s, out ulong v);
                    return v;
                }
                SteamUGC.GetQueryUGCMetadata(_queryResult.m_handle, i,
                    out string meta, Constants.k_cchDeveloperMetadataMax);
                SteamUGC.GetQueryUGCPreviewURL(_queryResult.m_handle, i,
                    out string previewUrl, 1024);
                Emit(new
                {
                    @event = "item",
                    id = d.m_nPublishedFileId.m_PublishedFileId.ToString(),
                    title = d.m_rgchTitle,
                    subs = Stat(EItemStatistic.k_EItemStatistic_NumSubscriptions),
                    favorites = Stat(EItemStatistic.k_EItemStatistic_NumFavorites),
                    comments = Stat(EItemStatistic.k_EItemStatistic_NumComments),
                    views = Stat(EItemStatistic.k_EItemStatistic_NumUniqueWebsiteViews),
                    votesUp = d.m_unVotesUp,
                    votesDown = d.m_unVotesDown,
                    score = d.m_flScore,
                    updated = d.m_rtimeUpdated,
                    visibility = (int)d.m_eVisibility,
                    tags = d.m_rgchTags, // 逗号分隔的工坊标签
                    meta, // 本工具发布时写入的版本号(老条目为空)
                    preview = previewUrl, // 封面图 CDN 直链
                    desc = d.m_rgchDescription, // 工坊现有简介(BBCode 全文)
                });
                total++;
            }
            SteamUGC.ReleaseQueryUGCRequest(q);
            if (n < Constants.kNumUGCResultsPerPage) break;
            page++;
        }
        Emit(new { @event = "result", ok = true, count = total });
        return 0;
    }

    private static void OnQuery(SteamUGCQueryCompleted_t r, bool ioFail)
    {
        _queryResult = r;
        _ioFailure = ioFail;
        _queryDone = true;
    }

    /// 原生库缺失/损坏时给出干净的 JSON 报错,而不是让进程裸崩。
    private static bool TryInit(object appId)
    {
        try
        {
            if (!SteamAPI.Init())
            {
                Fail($"无法连接 Steam:请确认 Steam 客户端正在运行并已登录,且该账号拥有 AppID {appId} 对应的游戏");
                return false;
            }
            return true;
        }
        catch (DllNotFoundException)
        {
            Fail("缺少 steam_api64.dll —— 它应与 CpSteamHelper.exe 在同一目录");
            return false;
        }
        catch (Exception e)
        {
            Fail("Steamworks 初始化异常: " + e.Message);
            return false;
        }
    }

    private static bool Pump(Func<bool> done, int timeoutSec)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (!done())
        {
            SteamAPI.RunCallbacks();
            if (sw.Elapsed.TotalSeconds > timeoutSec) return false;
            Thread.Sleep(100);
        }
        return true;
    }

    private static void OnCreateItem(CreateItemResult_t r, bool ioFail)
    {
        _createResult = r;
        _ioFailure = ioFail;
        _createDone = true;
    }

    private static void OnSubmit(SubmitItemUpdateResult_t r, bool ioFail)
    {
        _submitResult = r;
        _ioFailure = ioFail;
        _submitDone = true;
    }
}
