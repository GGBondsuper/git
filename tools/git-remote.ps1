# ============================================================
#  GitHub 一键推送 / 拉取
#  作用：自动找出当前可用的 GitHub 服务器地址，绕开被拦的那个
#  用法：双击 push-github.bat
# ============================================================

param(
    [string]$Task = "push"       # push / pull / fetch / sync
)

$ErrorActionPreference = 'Continue'
# 从脚本所在位置向上找 .git，最多找 6 层（脚本被复制到别处也不会找错仓库）
$RepoPath = $PSScriptRoot
for ($i = 0; $i -lt 6; $i++) {
    if ($RepoPath -and (Test-Path (Join-Path $RepoPath '.git'))) { break }
    $parent = Split-Path -Parent $RepoPath
    if (-not $parent -or $parent -eq $RepoPath) { $RepoPath = $null; break }
    $RepoPath = $parent
}
if (-not $RepoPath) {
    Write-Host ""
    Write-Host "  找不到 git 仓库（没有 .git 目录）。" -ForegroundColor Red
    Write-Host "  请把本工具放在仓库目录里面再运行。" -ForegroundColor Gray
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

$Candidates = @(
    '140.82.112.3',
    '140.82.113.3',
    '140.82.114.3',
    '140.82.121.3',
    '140.82.116.3',
    '140.82.112.6'
)

function Line { Write-Host ("-" * 58) -ForegroundColor DarkGray }
function Step($t) { Write-Host ""; Write-Host ">> $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "   [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "   [注意] $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "   [失败] $t" -ForegroundColor Red }
function Info($t) { Write-Host "          $t" -ForegroundColor Gray }

# ---------- 用 curl 完整探测一个 IP 是否真的能用（TCP 通不算通）----------
function Test-GitHubIp {
    param([string]$Ip, [int]$TimeoutSec = 10)

    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        try {
            $out = & $curl -s --noproxy "*" --max-time $TimeoutSec `
                --resolve "github.com:443:$Ip" `
                -o NUL -w "%{http_code}" "https://github.com" 2>$null
            if ("$out" -match '^[0-9]{3}$') {
                $code = [int]$out
                if ($code -ge 200 -and $code -lt 500) { return $true }
                return $false
            }
            return $false
        } catch {
            return $false
        }
    }

    # 没有 curl 时退回 TCP 探测（不如 curl 准，但聊胜于无）
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $task = $client.ConnectAsync($Ip, 443)
        $ok = ($task.Wait(3000) -and $client.Connected)
        $client.Close()
        return $ok
    } catch {
        return $false
    }
}

# ============================================================
Write-Host ""
Write-Host "  GitHub 一键操作  ->  $Task" -ForegroundColor White
Write-Host "  仓库：$RepoPath" -ForegroundColor DarkGray
Line

# ---------- 0. 环境准备：清掉系统里的代理变量 ----------
foreach ($v in @('http_proxy','https_proxy','all_proxy','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) {
    try { Set-Item -Path "env:$v" -Value $null -ErrorAction SilentlyContinue } catch { }
}

# ---------- 1. 找可用 IP ----------
Step "1 / 3  寻找当前可用的服务器地址（做完整连接测试）"
$good = @()
foreach ($ip in $Candidates) {
    if (Test-GitHubIp -Ip $ip -TimeoutSec 8) {
        Ok "$ip  可用"
        $good += $ip
    } else {
        Write-Host "   $ip  不可用" -ForegroundColor DarkGray
    }
}

if ($good.Count -eq 0) {
    Warn "一个可用的地址都没找到"
    Info "这通常说明当前网络出口整体不通，不是配置问题"
    Info "可以试试：① 换成手机热点   ② 打开加速器（Watt Toolkit）后再运行"
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

Write-Host ""
Ok "共 $($good.Count) 个可用，逐个尝试"

# ---------- 2. 执行 git 命令 ----------
Step "2 / 3  执行 git $Task"
$succeeded = $false
$lastOut = ""

foreach ($ip in $good) {
    Write-Host ""
    Write-Host "   尝试 $ip ..." -ForegroundColor DarkGray

    $gitArgs = @(
        '-C', $RepoPath,
        '-c', "http.curloptResolve=github.com:443:$ip",
        '-c', 'http.proxy=',
        '-c', 'http.lowSpeedLimit=0',
        '-c', 'http.postBuffer=524288000'
    )

    switch ($Task) {
        'sync' {
            Write-Host "   -> git pull" -ForegroundColor DarkGray
            & git @gitArgs pull --rebase --autostash 2>&1 | Tee-Object -Variable lastOut | Write-Host
            Write-Host "   -> git push" -ForegroundColor DarkGray
            & git @gitArgs push 2>&1 | Tee-Object -Variable lastOut | Write-Host
        }
        default {
            & git @gitArgs $Task 2>&1 | Tee-Object -Variable lastOut | Write-Host
        }
    }

    if ($LASTEXITCODE -eq 0) {
        $succeeded = $true
        Ok "完成（使用 $ip）"
        break
    } else {
        Warn "$ip 这条路失败了，换下一个"
    }
}

# ---------- 3. 结果 ----------
Line
Write-Host ""
if ($succeeded) {
    Write-Host "  成功了。" -ForegroundColor Green
    Write-Host ""
    Write-Host "  看看仓库状态：" -ForegroundColor Gray
    & git -C $RepoPath status -sb

    if ($Task -eq 'push' -or $Task -eq 'sync') {
        Write-Host ""
        Write-Host "  打开看看：https://github.com/GGBondsuper/git" -ForegroundColor DarkCyan
    }
} else {
    Write-Host "  全部线路都失败了。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  可以做的：" -ForegroundColor Gray
    Write-Host "   1. 先跑一次 check-github.bat，看现在到底哪个地址活着"
    Write-Host "   2. 换网络（手机热点）再试"
    Write-Host "   3. 打开加速器（Watt Toolkit）后重跑本工具"
    Write-Host ""
    Write-Host "  你的提交不会丢，Git 会一直等着。" -ForegroundColor DarkGray
}
Write-Host ""
Read-Host "按回车键退出"
