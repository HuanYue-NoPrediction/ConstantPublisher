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
        string? Version);

    private static bool _createDone;
    private static bool _submitDone;
    private static bool _queryDone;
    private static bool _ioFailure;
    private static CreateItemResult_t _createResult;
    private static SubmitItemUpdateResult_t _submitResult;
    private static SteamUGCQueryCompleted_t _queryResult;

    private static void Emit(object o) =>
        Console.WriteLine(JsonSerializer.Serialize(o));

    private static void Fail(string error, int eresult = 0) =>
        Emit(new { @event = "result", ok = false, error, eresult });

    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);

        // 模式二:list <appid> —— 借 Steam 会话列出当前账号名下的工坊条目,零配置
        if (args.Length >= 1 && args[0] == "list")
        {
            var listAppId = args.Length >= 2 && uint.TryParse(args[1], out var a) ? a : 322330u;
            Environment.SetEnvironmentVariable("SteamAppId", listAppId.ToString());
            Environment.SetEnvironmentVariable("SteamGameId", listAppId.ToString());
            if (!TryInit(listAppId)) return 0;
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

        // 以目标游戏的身份接入 Steam(要求当前账号拥有该游戏)。
        // 必须在 Init 之前设置,替代 steam_appid.txt。
        Environment.SetEnvironmentVariable("SteamAppId", req.AppId.ToString());
        Environment.SetEnvironmentVariable("SteamGameId", req.AppId.ToString());

        if (!TryInit(req.AppId)) return 0;

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
            var cr = CallResult<CreateItemResult_t>.Create(OnCreateItem);
            cr.Set(call);
            if (!Pump(() => _createDone, 60))
            {
                Fail("CreateItem 超时(60 秒)");
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

        Emit(new { @event = "stage", stage = "StartItemUpdate · 填充元数据" });
        var h = SteamUGC.StartItemUpdate(appId, fileId);
        SteamUGC.SetItemTitle(h, req.Title);
        SteamUGC.SetItemDescription(h, req.Description);
        SteamUGC.SetItemContent(h, req.ContentFolder);
        if (!string.IsNullOrEmpty(req.PreviewFile))
        {
            SteamUGC.SetItemPreview(h, req.PreviewFile);
        }
        SteamUGC.SetItemVisibility(h, (ERemoteStoragePublishedFileVisibility)req.Visibility);
        if (req.Tags is { Length: > 0 })
        {
            SteamUGC.SetItemTags(h, new List<string>(req.Tags));
        }
        if (!string.IsNullOrEmpty(req.Version))
        {
            // 把 modinfo 版本写进 UGC metadata:list 模式读回,任何机器重新绑定都能拿到工坊版本
            SteamUGC.SetItemMetadata(h, req.Version);
        }

        Emit(new { @event = "stage", stage = "SubmitItemUpdate · 开始上传" });
        var sub = SteamUGC.SubmitItemUpdate(h, req.ChangeNote);
        var sr = CallResult<SubmitItemUpdateResult_t>.Create(OnSubmit);
        sr.Set(sub);

        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (!_submitDone)
        {
            SteamAPI.RunCallbacks();
            var status = SteamUGC.GetItemUpdateProgress(h, out ulong done, out ulong total);
            if (total > 0)
            {
                Emit(new { @event = "progress", status = status.ToString(), done, total });
            }
            if (sw.Elapsed > TimeSpan.FromMinutes(30))
            {
                Fail("上传超时(30 分钟)");
                return 0;
            }
            Thread.Sleep(200);
        }

        if (_ioFailure || _submitResult.m_eResult != EResult.k_EResultOK)
        {
            Fail("SubmitItemUpdate 失败", (int)_submitResult.m_eResult);
            return 0;
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

    private static int RunList(AppId_t appId)
    {
        var account = SteamUser.GetSteamID().GetAccountID();
        uint page = 1;
        var total = 0;
        while (page <= 10)
        {
            // nCreatorAppID 必须给 0(不限):经官方 ModUploader 上传的老模组,
            // 创建者 App 是 "Don't Starve Mod Tools" 而非游戏本身,按游戏过滤会全部漏掉
            var q = SteamUGC.CreateQueryUserUGCRequest(
                account,
                EUserUGCList.k_EUserUGCList_Published,
                EUGCMatchingUGCType.k_EUGCMatchingUGCType_Items,
                EUserUGCListSortOrder.k_EUserUGCListSortOrder_LastUpdatedDesc,
                new AppId_t(0), appId, page);
            SteamUGC.SetReturnMetadata(q, true);
            SteamUGC.SetReturnLongDescription(q, true);
            _queryDone = false;
            var cr = CallResult<SteamUGCQueryCompleted_t>.Create(OnQuery);
            cr.Set(SteamUGC.SendQueryUGCRequest(q));
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
