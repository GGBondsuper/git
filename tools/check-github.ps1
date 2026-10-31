# ============================================================
#  GitHub 连通性自检工具
#  作用：一跑就知道「是地址变了、还是网络断了」
#  用法：双击 check-github.bat（不需要管理员权限）
# ============================================================

$ErrorActionPreference = 'Continue'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$CurlExe = Join-Path $env:SystemRoot 'System32\curl.exe'

$Candidates = @(
    '140.82.112.3',
    '140.82.113.3',
    '140.82.114.3',
    '140.82.121.3',
    '140.82.116.3',
    '140.82.112.6',
    '20.205.243.166'
)

# ---------- 环境自检：curl.exe 是本脚本唯一的硬依赖 ----------
# 没有它，所有探测都会失败，结论会误报成「网络不通」——必须先拦住
if (-not (Test-Path $CurlExe)) {
    Write-Host ""
    Write-Host "  [失败] 找不到 curl.exe" -ForegroundColor Red
    Write-Host "         期望路径：$CurlExe" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  curl 是 Windows 10（1803 及以后）系统自带的组件。" -ForegroundColor Gray
    Write-Host "  你的系统较旧，或者这个文件被安全软件移除了。" -ForegroundColor Gray
    Write-Host "  处理：升级 Windows，或装好 curl 后再运行本工具。" -ForegroundColor Gray
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

function Line { Write-Host ("-" * 62) -ForegroundColor DarkGray }
function Step($t) { Write-Host ""; Write-Host ">> $t" -ForegroundColor Cyan }

# ---------- 完整 HTTPS 探测（指定 IP，跳过 DNS）----------
function Test-GitHubIp {
    param([string]$Ip, [int]$TimeoutSec = 8)
    try {
        $out = & $CurlExe -s --noproxy "*" --max-time $TimeoutSec `
            --resolve "github.com:443:$Ip" `
            -o NUL -w "%{http_code}@%{time_appconnect}" "https://github.com" 2>$null
        $s = "$out"
        if ($s -match '^(\d{3})@([\d.]+)$') {
            $code = [int]$Matches[1]
            $tls = [double]$Matches[2]
            $ok = ($code -ge 200 -and $code -lt 400) -or $code -eq 401 -or $code -eq 403
            return @{ Ok = $ok; Code = $code; Tls = $tls }
        }
        return @{ Ok = $false; Code = 0; Tls = 0 }
    } catch {
        return @{ Ok = $false; Code = 0; Tls = 0 }
    }
}

# ---------- 普通域名探测（走系统 DNS，直连不走代理）----------
function Test-Url {
    param([string]$Url, [int]$TimeoutSec = 12)
    try {
        $out = & $CurlExe -s --noproxy "*" --max-time $TimeoutSec -o NUL `
            -w "%{http_code}@%{time_total}@%{remote_ip}" $Url 2>$null
        $s = "$out"
        if ($s -match '^(\d{3})@([\d.]+)@(.*)$') {
            return @{ Code = [int]$Matches[1]; Ms = [int]([double]$Matches[2] * 1000); Ip = $Matches[3] }
        }
        return @{ Code = 0; Ms = 0; Ip = '' }
    } catch {
        return @{ Code = 0; Ms = 0; Ip = '' }
    }
}

# ============================================================
Write-Host ""
Write-Host "  GitHub 连通性自检" -ForegroundColor White
Write-Host "  检查时间 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Line

# ---------- 1. 系统解析 ----------
Step "1. 系统当前把 github.com 解析成哪个地址"
try {
    $addrs = [System.Net.Dns]::GetHostAddresses('github.com') | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
    if ($addrs) {
        foreach ($a in $addrs) { Write-Host "   $($a.IPAddressToString)" -ForegroundColor White }
    } else {
        Write-Host "   解析不到 IPv4 地址" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   解析失败：$($_.Exception.Message)" -ForegroundColor Red
}

# ---------- 2. hosts 现状 ----------
Step "2. hosts 文件里的 github 记录"
$hostsHit = @()
try {
    $lines = [System.IO.File]::ReadAllLines($HostsPath)
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#') -and $t -match 'github') { $hostsHit += $t }
    }
} catch { }
if ($hostsHit.Count -gt 0) {
    foreach ($h in $hostsHit) { Write-Host "   $h" -ForegroundColor Green }
} else {
    Write-Host "   （没有任何 github 记录，走系统 DNS）" -ForegroundColor Yellow
}

# ---------- 3. 候选 IP 的完整可用性 ----------
Step "3. 候选服务器可用性（完整 HTTPS，TCP 通不算通）"
$good = @()
foreach ($ip in $Candidates) {
    $r = Test-GitHubIp -Ip $ip -TimeoutSec 8
    if ($r.Ok) {
        Write-Host ("   {0,-18} 可用   HTTP {1}   TLS {2}s" -f $ip, $r.Code, $r.Tls) -ForegroundColor Green
        $good += $ip
    } else {
        Write-Host ("   {0,-18} 不可用" -f $ip) -ForegroundColor DarkGray
    }
}

# ---------- 4. 各域名状态 ----------
Step "4. 各域名状态（走系统 DNS，直连）"
$targets = @(
    @{ Name = 'github.com';                Url = 'https://github.com' },
    @{ Name = 'api.github.com';            Url = 'https://api.github.com' },
    @{ Name = 'codeload.github.com';       Url = 'https://codeload.github.com' },
    @{ Name = 'raw.githubusercontent.com'; Url = 'https://raw.githubusercontent.com' }
)
$ghCode = 0
$ghMs   = 0
foreach ($t in $targets) {
    $r = Test-Url -Url $t.Url -TimeoutSec 12
    # 能拿到任何 HTTP 响应（含 401/403/404）就说明路是通的
    $reachable = ($r.Code -ge 200 -and $r.Code -lt 400) -or `
                 $r.Code -eq 401 -or $r.Code -eq 403 -or $r.Code -eq 404
    if ($r.Code -eq 0) {
        Write-Host ("   {0,-30} 失败（12 秒内没有任何响应）" -f $t.Name) -ForegroundColor Red
    } elseif (-not $reachable) {
        Write-Host ("   {0,-30} 异常  HTTP {1}" -f $t.Name, $r.Code) -ForegroundColor Red
    } elseif ($r.Ms -gt 3000) {
        # 重要：200 不代表好用。浏览器对单个请求的耐心远小于 3 秒
        Write-Host ("   {0,-30} {1}   {2} ms   慢 <- 浏览器基本等不到" -f $t.Name, $r.Code, $r.Ms) -ForegroundColor Yellow
    } else {
        Write-Host ("   {0,-30} {1}   {2} ms   ({3})" -f $t.Name, $r.Code, $r.Ms, $r.Ip) -ForegroundColor Green
    }
    if ($t.Name -eq 'github.com') { $ghCode = $r.Code; $ghMs = $r.Ms }
}

# ---------- 5. 结论 ----------
Line
Write-Host ""
Write-Host "  结论" -ForegroundColor White
Write-Host ""

$ghOk   = ($ghCode -ge 200 -and $ghCode -lt 400)
$ghSlow = ($ghMs -gt 3000)

if ($ghOk -and -not $ghSlow) {
    Write-Host "  系统默认线路是通的（github.com 响应 $($ghMs) ms），直接 git push 就行。" -ForegroundColor Green
    if ($good.Count -eq 0) {
        Write-Host "  （候选地址反而都不通，但你并不需要它们）" -ForegroundColor DarkGray
    }
} elseif ($ghOk -and $ghSlow) {
    # 最容易被误判的情况：状态码 200，但慢到浏览器不能用
    Write-Host "  github.com 能连上，但响应 $($ghMs) ms —— 这个速度浏览器打不开。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  为什么：GitHub 首页约 530 KB，还要再加载几十个静态资源。" -ForegroundColor Gray
    Write-Host "  单个请求就要 3 秒以上，浏览器等不到就放弃，表现为一直转圈或超时。" -ForegroundColor Gray
    Write-Host "  （git push 反而还能用：一次连接慢慢传就行，不追求秒回）" -ForegroundColor Gray
    Write-Host ""
    if ($good.Count -gt 0) {
        Write-Host "  想让浏览器 / VS Code 也通：" -ForegroundColor Gray
        Write-Host "   右键 fix-github.bat -> 以管理员身份运行" -ForegroundColor DarkCyan
        Write-Host "   它会把 github.com 改指向下面这些更快地址之一：" -ForegroundColor Gray
        Write-Host "   $($good -join '  ')" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  只想推代码：双击 push-github.bat（不需要管理员权限）" -ForegroundColor DarkGray
    } else {
        Write-Host "  但候选地址也都不通，眼下换路换不了。" -ForegroundColor Yellow
        Write-Host "   1. 换手机热点试一次（30 秒能判断是不是校园网的事）" -ForegroundColor Gray
        Write-Host "   2. 打开加速器（Watt Toolkit / FastGithub）" -ForegroundColor Gray
        Write-Host "   3. 过一会儿再试（这条线路是间歇性的）" -ForegroundColor Gray
    }
} elseif ($good.Count -gt 0) {
    Write-Host "  系统默认线路不通，但有 $($good.Count) 个地址可用。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  推荐做法（二选一）：" -ForegroundColor Gray
    Write-Host "   A. 只想推代码  -> 双击 push-github.bat（自动挑可用地址，无需权限）" -ForegroundColor DarkCyan
    Write-Host "   B. 想让浏览器/VS Code 也通 -> 右键 fix-github.bat 以管理员运行" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  可用地址：$($good -join '  ')" -ForegroundColor DarkGray
} else {
    Write-Host "  所有地址都不通，当前网络整体无法访问 GitHub。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  这不是配置问题，做这几件事才有用：" -ForegroundColor Gray
    Write-Host "   1. 换手机热点试一次（30 秒就能判断是不是校园网的事）"
    Write-Host "   2. 打开加速器（Watt Toolkit / FastGithub）"
    Write-Host "   3. 过一会儿再试（这条线路是间歇性的）"
}

Write-Host ""
Write-Host "  提示：GitHub 的 IP 会变动，这条路今天通明天可能就断。" -ForegroundColor DarkGray
Write-Host "        本脚本每次都现场实测，所以不用记 IP，随时重跑即可。" -ForegroundColor DarkGray
Write-Host ""
Read-Host "按回车键退出"
