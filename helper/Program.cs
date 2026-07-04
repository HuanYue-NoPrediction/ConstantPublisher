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
        string[]? Tags);

    private static bool _createDone;
    private static bool _submitDone;
    private static bool _ioFailure;
    private static CreateItemResult_t _createResult;
    private static SubmitItemUpdateResult_t _submitResult;

    private static void Emit(object o) =>
        Console.WriteLine(JsonSerializer.Serialize(o));

    private static void Fail(string error, int eresult = 0) =>
        Emit(new { @event = "result", ok = false, error, eresult });

    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);

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

        if (!SteamAPI.Init())
        {
            Fail($"无法连接 Steam:请确认 Steam 客户端正在运行并已登录,且该账号拥有 AppID {req.AppId} 对应的游戏");
            return 0;
        }

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
