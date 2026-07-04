/// Steam EResult 错误码 → 人话。官方工具只报数字,这里必须翻译。
const Map<int, String> kEResult = {
  1: 'OK:成功',
  2: 'Fail:通用失败,查看日志上下文',
  3: 'NoConnection:无法连接 Steam,检查网络或 Steam 客户端',
  5: 'InvalidPassword:密码错误或登录凭据失效,请重新登录',
  6: 'LoggedInElsewhere:账号在别处登录',
  8: 'InvalidParam:参数无效 —— 常见于 VDF 字段错误',
  9: 'FileNotFound:找不到文件,检查内容目录与预览图路径',
  10: 'Busy:Steam 忙,稍后重试',
  15: 'AccessDenied:无权限 —— 账号是否拥有该游戏?是否为条目所有者?',
  16: 'Timeout:超时,稍后重试',
  20: 'ServiceUnavailable:Steam 服务不可用,稍后重试',
  25: 'LimitExceeded:超出配额/频率限制 —— 云配额、预览图过大或提交过于频繁,稍后重试',
  33: 'ExpiredToken:登录令牌过期,需重新登录',
  50: 'Banned:账号被封禁',
  84: 'RateLimitExceeded:提交太频繁,被限流,等几分钟',
};

String decodeEResult(int code) =>
    'EResult $code = ${kEResult[code] ?? '未知错误,查阅 steamerrors.com/$code'}';
