#!/usr/bin/env python3
"""把 Steamworks.NET 的 macOS 版 DLL 打补丁,使其能在 arm64 进程里加载。

背景:Steamworks.NET 的 NuGet 包只提供 osx-x64 的托管 DLL(PE 头 Machine 标成
x64),没有 osx-arm64 版。它虽是纯 IL(架构无关),但 .NET 加载器认死 Machine
标记,在 arm64 进程里会拒绝加载(报 "architecture is not compatible"),导致
helper 一启动就崩(表现为找不到 Steamworks.NET)。

本脚本下载 osx-x64 版(带正确的 macOS 结构体打包),把 PE 头 Machine 字段从
x64(0x8664) 改成 arm64(0xAA64) —— 纯 IL 改这个标记是安全的,代码照常运行。
构建脚本用它覆盖 helper_out 里那份不可用的 DLL。

用法:  python3 patch_steamworks.py <输出路径>
"""

import io
import struct
import sys
import urllib.request
import zipfile

VERSION = "20.2.0"
NUPKG = f"https://www.nuget.org/api/v2/package/Steamworks.NET/{VERSION}"
ENTRY = "runtimes/osx-x64/lib/netstandard2.1/Steamworks.NET.dll"


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "Steamworks.NET.dll"

    print(f"下载 Steamworks.NET {VERSION} …")
    data = urllib.request.urlopen(NUPKG, timeout=120).read()
    raw = zipfile.ZipFile(io.BytesIO(data)).read(ENTRY)

    b = bytearray(raw)
    e_lfanew = struct.unpack_from("<I", b, 0x3C)[0]
    assert b[e_lfanew:e_lfanew + 4] == b"PE\0\0", "不是有效 PE"
    machine_off = e_lfanew + 4
    old = struct.unpack_from("<H", b, machine_off)[0]
    struct.pack_into("<H", b, machine_off, 0xAA64)  # IMAGE_FILE_MACHINE_ARM64

    with open(out, "wb") as f:
        f.write(b)
    print(f"✓ 已打补丁: Machine 0x{old:04X} -> 0xAA64 (ARM64)  ->  {out}")


if __name__ == "__main__":
    main()
