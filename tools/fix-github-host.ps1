# ============================================================
#  GitHub 访问修复工具
#  作用：把 github.com 指向现场实测可用的服务器地址
#  用法：右键 fix-github.bat -> 以管理员身份运行
# ============================================================

param(
    [switch]$Restore,          # 恢复模式：把 hosts 还原成最干净的备份
    [string]$PinIp = ""        # 手动指定 IP，不传则自动选最快的
)

$ErrorActionPreference = 'Continue'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$CurlExe   = Join-Path $env:SystemRoot 'System32\curl.exe'

# 实测可用的 GitHub 前端 IP（140.82.x.x 段）
$Candidates = @(
    '140.82.112.3',
    '140.82.113.3',
    '140.82.114.3',
    '140.82.121.3',
    '140.82.116.3',
    '140.82.112.6'
)

# ---------- 输出helper ----------
function Line { Write-Host ("-" * 58) -ForegroundColor DarkGray }
function Step($t) { Write-Host ""; Write-Host ">> $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "   [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "   [注意] $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "   [失败] $t" -ForegroundColor Red }
function Info($t) { Write-Host "          $t" -ForegroundColor Gray }

# ---------- 完整 HTTPS 探测：指定 IP 访问 github.com ----------
# 注意：只看 TCP 握手会误判——有些中间设备会应答 SYN 之后掐断 TLS
function Test-GitHubIp {
    param([string]$Ip, [int]$TimeoutSec = 8)
    try {
        $out = & $CurlExe -s --noproxy "*" --max-time $TimeoutSec `
            --resolve "github.com:443:$Ip" `
            -o NUL -w "%{http_code}@%{time_appconnect}" "https://github.com" 2>$null
        $s = "$out"
        if ($s -match '^(\d{3})@([\d.]+)$') {
            $code = [int]$Matches[1]
            $tls  = [double]$Matches[2]
            $ok = ($code -ge 200 -and $code -lt 400) -or $code -eq 401 -or $code -eq 403
            return @{ Ok = $ok; Code = $code; Tls = $tls }
        }
        return @{ Ok = $false; Code = 0; Tls = 0 }
    } catch {
        return @{ Ok = $false; Code = 0; Tls = 0 }
    }
}

# ---------- 普通 HTTPS 探测（走系统 DNS / hosts）----------
function Test-Https {
    param([string]$Url, [int]$TimeoutSec = 12)
    try {
        $out = & $CurlExe -s --noproxy "*" --max-time $TimeoutSec -o NUL -w "%{http_code}" $Url 2>$null
        $s = "$out"
        if ($s -match '^(\d{3})$') { return [int]$Matches[1] }
        return 0
    } catch {
        return 0
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================
Write-Host ""
Write-Host "  GitHub 访问修复工具" -ForegroundColor White
Write-Host "  把 github.com 指向现场实测可用的服务器地址" -ForegroundColor DarkGray
Line

# ---------- 1. 权限 ----------
Step "1 / 5  检查管理员权限"
if (-not (Test-IsAdmin)) {
    Fail "当前不是管理员，无法修改 hosts"
    Info "请关掉这个窗口，右键 fix-github.bat"
    Info "选择【以管理员身份运行】"
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}
Ok "管理员权限已确认"

# ---------- 恢复模式 ----------
if ($Restore) {
    Step "恢复模式：从备份还原 hosts"
    $dir = Split-Path $HostsPath
    $baks = Get-ChildItem -Path $dir -Filter 'hosts.bak-*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    if (-not $baks) {
        Fail "没找到任何备份文件（hosts.bak-*）"
        Read-Host "按回车键退出"
        exit 1
    }
    $latest = $baks[0]
    Info "使用备份：$($latest.Name)  ($($latest.LastWriteTime))"
    try {
        $item = Get-Item $HostsPath
        if ($item.IsReadOnly) { $item.IsReadOnly = $false }
        Copy-Item $latest.FullName $HostsPath -Force
        Ok "hosts 已还原"
        ipconfig /flushdns | Out-Null
        Ok "DNS 缓存已刷新"
    } catch {
        Fail "还原失败：$($_.Exception.Message)"
    }
    Write-Host ""
    Read-Host "按回车键退出"
    exit 0
}

# ---------- 2. 选 IP ----------
Step "2 / 5  现场测试候选服务器（做完整连接测试）"
$bestIp = $null
$bestTls = 999.0
$alive = @()

foreach ($ip in $Candidates) {
    $r = Test-GitHubIp -Ip $ip -TimeoutSec 8
    if ($r.Ok) {
        Ok ("{0,-16} 可用   HTTP {1}   TLS {2}s" -f $ip, $r.Code, $r.Tls)
        $alive += $ip
        if ($r.Tls -lt $bestTls) { $bestTls = $r.Tls; $bestIp = $ip }
    } else {
        Fail ("{0,-16} 不可用" -f $ip)
    }
}

if ($PinIp -ne "") {
    $bestIp = $PinIp
    Info "改用你手动指定的 IP：$PinIp"
}

if (-not $bestIp) {
    Warn "所有候选地址都不可用"
    Info "说明问题不在 DNS，而是当前网络整体连不上 GitHub"
    Info "建议：换手机热点试试，或用 Watt Toolkit 这类加速工具"
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

Write-Host ""
Ok "选中：$bestIp （TLS 握手 $bestTls 秒）"

# ---------- 3. 备份 ----------
Step "3 / 5  备份原始 hosts"
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$HostsPath.bak-$stamp"
try {
    Copy-Item $HostsPath $backup -Force
    Ok "已备份到 hosts.bak-$stamp"
} catch {
    Fail "备份失败：$($_.Exception.Message)"
    Read-Host "按回车键退出"
    exit 1
}

# ---------- 4. 写入 ----------
Step "4 / 5  写入新记录"
try {
    $item = Get-Item $HostsPath
    if ($item.IsReadOnly) {
        $item.IsReadOnly = $false
        Info "已清除 hosts 的只读属性"
    }

    $raw = [System.IO.File]::ReadAllLines($HostsPath, [System.Text.Encoding]::UTF8)

    # 删掉旧的 github 相关记录（保留以 # 开头的注释行）
    $kept = @()
    $removed = 0
    foreach ($l in $raw) {
        $t = $l.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#') -and ($t -match 'github\.com' -or $t -match 'github\.global')) {
            $removed++
        } else {
            $kept += $l
        }
    }
    if ($removed -gt 0) { Info "清理掉 $removed 条旧记录" }

    # 去掉上一轮留下的标记行
    $kept = $kept | Where-Object { $_ -notmatch 'WorkBuddy GitHub Fix' }

    $newLines = @()
    $newLines += ''
    $newLines += '# === WorkBuddy GitHub Fix ==='
    $newLines += "# 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $newLines += '# 若哪天又不通了，重新运行 fix-github.bat 会自动换一个地址'
    $newLines += "$bestIp    github.com"
    $newLines += '# === WorkBuddy GitHub Fix End ==='

    $output = $kept + $newLines
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($HostsPath, $output, $enc)

    Ok "已写入：$bestIp  github.com"
} catch {
    Fail "写入失败：$($_.Exception.Message)"
    Info "可以从备份恢复：$backup"
    Read-Host "按回车键退出"
    exit 1
}

# ---------- 5. 验证 ----------
Step "5 / 5  刷新缓存并验证"
ipconfig /flushdns | Out-Null
Ok "DNS 缓存已刷新"

Start-Sleep -Milliseconds 800

$code = Test-Https -Url 'https://github.com' -TimeoutSec 15
if ($code -ge 200 -and $code -lt 400) {
    Ok "github.com 返回 HTTP $code   —— 路通了"
} elseif ($code -eq 401 -or $code -eq 403) {
    Ok "github.com 返回 HTTP $code   —— 服务器在等认证，路是通的"
} else {
    Warn "github.com 返回 HTTP $code   —— 还没完全通"
    Info "可以换一个地址：右键运行 fix-github.bat 时加 -PinIp 参数"
    Info "可用的备选：$($alive -join '  ')"
}

$codeApi = Test-Https -Url 'https://api.github.com' -TimeoutSec 10
if ($codeApi -ge 200 -and $codeApi -lt 400) {
    Ok "api.github.com 返回 HTTP $codeApi"
} else {
    Warn "api.github.com 返回 HTTP $codeApi"
}

Line
Write-Host ""
Write-Host "  下一步" -ForegroundColor White
Write-Host "  1. 关掉所有浏览器窗口，重新打开（浏览器有自己的 DNS 缓存）"
Write-Host "  2. 打开 Git Bash 试一次推送："
Write-Host ""
Write-Host "       cd /d/git" -ForegroundColor DarkCyan
Write-Host "       git push" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  3. 想撤销这次修改：运行 restore-github.bat" -ForegroundColor Gray
Write-Host "  4. 以后哪天又不通了：先跑 check-github.bat 看看，再重跑本工具" -ForegroundColor Gray
Write-Host ""
Read-Host "按回车键退出"
