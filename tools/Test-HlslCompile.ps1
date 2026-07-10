param(
    [string]$Path = (Join-Path $PSScriptRoot '..\blackhole.hlsl'),
    [string]$EntryPoint = 'main',
    [string]$Profile = 'ps_4_0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('BlackholeD3DCompiler' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class BlackholeD3DCompiler
{
    [DllImport("D3DCompiler_47.dll", CharSet = CharSet.Ansi)]
    public static extern int D3DCompile(
        byte[] srcData,
        UIntPtr srcDataSize,
        string sourceName,
        IntPtr defines,
        IntPtr include,
        string entrypoint,
        string target,
        uint flags1,
        uint flags2,
        out IntPtr code,
        out IntPtr errorMsgs);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate IntPtr GetBufferPointerDelegate(IntPtr self);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate UIntPtr GetBufferSizeDelegate(IntPtr self);

    public static string BlobToAnsiString(IntPtr blob)
    {
        if (blob == IntPtr.Zero)
        {
            return "";
        }

        var vtbl = Marshal.ReadIntPtr(blob);
        var getBufferPointerPtr = Marshal.ReadIntPtr(vtbl, 3 * IntPtr.Size);
        var getBufferSizePtr = Marshal.ReadIntPtr(vtbl, 4 * IntPtr.Size);
        var getBufferPointer = (GetBufferPointerDelegate)Marshal.GetDelegateForFunctionPointer(
            getBufferPointerPtr, typeof(GetBufferPointerDelegate));
        var getBufferSize = (GetBufferSizeDelegate)Marshal.GetDelegateForFunctionPointer(
            getBufferSizePtr, typeof(GetBufferSizeDelegate));
        var ptr = getBufferPointer(blob);
        var len = checked((int)getBufferSize(blob));
        return Marshal.PtrToStringAnsi(ptr, len);
    }

    public static void ReleaseBlob(IntPtr blob)
    {
        if (blob != IntPtr.Zero)
        {
            Marshal.Release(blob);
        }
    }
}
'@
}

$Path = (Resolve-Path -LiteralPath $Path).Path
$bytes = [IO.File]::ReadAllBytes($Path)
$code = [IntPtr]::Zero
$errors = [IntPtr]::Zero
$hr = [BlackholeD3DCompiler]::D3DCompile(
    $bytes,
    [UIntPtr]::new([uint64]$bytes.Length),
    $Path,
    [IntPtr]::Zero,
    [IntPtr]::Zero,
    $EntryPoint,
    $Profile,
    0,
    0,
    [ref]$code,
    [ref]$errors)

try {
    if ($hr -ne 0) {
        $message = [BlackholeD3DCompiler]::BlobToAnsiString($errors)
        throw ("D3DCompile failed with HRESULT 0x{0:x8}`n{1}" -f ($hr -band 0xffffffff), $message)
    }

    Write-Host "OK: $Path compiled as $Profile / $EntryPoint"
}
finally {
    [BlackholeD3DCompiler]::ReleaseBlob($code)
    [BlackholeD3DCompiler]::ReleaseBlob($errors)
}
