Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$exeDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)

# ── Lecture du .env ───────────────────────────────────────────────
$envFile = "$exeDir\.env"
if (-not (Test-Path $envFile)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Fichier .env introuvable !`n`nCopie .env.example en .env et remplis les valeurs.",
        "MC Dashboard", [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+?)\s*=\s*(.+)\s*$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
}

$playitSecret  = $envVars['PLAYIT_SECRET']
$playitAddress = $envVars['PLAYIT_ADDRESS']
$githubToken   = $envVars['GITHUB_TOKEN']
$gistId        = $envVars['GIST_ID']
$gitRepoUrl    = $envVars['GIT_REPO_URL']
$playitExe     = "$exeDir\playit.exe"
$machineName   = $env:COMPUTERNAME

# ── Fenêtre de progression ────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "MC Dashboard"
$form.Size = New-Object System.Drawing.Size(420, 160)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(13, 17, 23)

$lblStep = New-Object System.Windows.Forms.Label
$lblStep.ForeColor = [System.Drawing.Color]::FromArgb(74, 222, 128)
$lblStep.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblStep.AutoSize = $true
$lblStep.Location = New-Object System.Drawing.Point(20, 18)
$lblStep.Text = "Initialisation..."
$form.Controls.Add($lblStep)

$lblDetail = New-Object System.Windows.Forms.Label
$lblDetail.ForeColor = [System.Drawing.Color]::FromArgb(100, 120, 140)
$lblDetail.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblDetail.AutoSize = $true
$lblDetail.Location = New-Object System.Drawing.Point(20, 42)
$lblDetail.Text = ""
$form.Controls.Add($lblDetail)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 75)
$progress.Size = New-Object System.Drawing.Size(375, 12)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Style = "Continuous"
$form.Controls.Add($progress)

$form.Show()
[System.Windows.Forms.Application]::DoEvents()

function Set-Status($step, $detail, $pct) {
    $lblStep.Text = $step
    $lblDetail.Text = $detail
    $progress.Value = $pct
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Error($msg) {
    $form.Hide()
    [System.Windows.Forms.MessageBox]::Show($msg, "MC Dashboard", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

# ── Fonctions Gist ────────────────────────────────────────────────
function Get-GistStatus {
    try {
        $headers = @{ Authorization = "token $githubToken"; "User-Agent" = "MC-Launcher" }
        $gist = Invoke-RestMethod -Uri "https://api.github.com/gists/$gistId" -Headers $headers
        return $gist.files."mc-status.json".content | ConvertFrom-Json
    } catch { return $null }
}

function Set-GistStatus($running, $hostName) {
    try {
        $content = @{ running = $running; hostName = $hostName; since = (Get-Date -Format "o") } | ConvertTo-Json
        $body = @{ files = @{ "mc-status.json" = @{ content = $content } } } | ConvertTo-Json -Depth 5
        $headers = @{ Authorization = "token $githubToken"; "User-Agent" = "MC-Launcher"; "Content-Type" = "application/json" }
        Invoke-RestMethod -Method Patch -Uri "https://api.github.com/gists/$gistId" -Headers $headers -Body $body | Out-Null
    } catch {}
}

function Test-LocalServer {
    try {
        $result = & docker inspect -f '{{.State.Running}}' mc-serveur 2>$null
        return $result.Trim() -eq "true"
    } catch { return $false }
}

# ── Mise à jour auto ──────────────────────────────────────────────
Set-Status "Mise à jour..." "Récupération des dernières mises à jour" 5
try { Set-Location $exeDir; & git pull origin master 2>$null | Out-Null } catch {}

# ── Vérification locale ───────────────────────────────────────────
Set-Status "Vérification..." "Vérification du statut local" 10
if (Test-LocalServer) {
    $form.Close()
    [System.Windows.Forms.MessageBox]::Show("Le serveur est déjà lancé sur cette machine.", "MC Dashboard", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    Start-Process "http://localhost:3000"
    exit
}

# ── Vérification Gist ─────────────────────────────────────────────
Set-Status "Vérification..." "Vérification si le serveur tourne ailleurs" 15
$status = Get-GistStatus
if ($status -and $status.running) {
    if ($status.hostName -eq $machineName) {
        Set-GistStatus $false ""
    } else {
        $since = ""
        if ($status.since) {
            $date = [DateTime]::Parse($status.since)
            $since = "`nDepuis : " + $date.ToString("HH:mm 'le' dd/MM")
        }
        $form.Hide()
        $msg = "Le serveur est déjà en ligne chez $($status.hostName).$since`n`nContacte-le pour savoir quand il s'arrête."
        [System.Windows.Forms.MessageBox]::Show($msg, "Serveur déjà en ligne", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        exit
    }
}

# ── Docker ────────────────────────────────────────────────────────
$dockerRunning = $false
try { & docker ps 2>$null | Out-Null; $dockerRunning = (Test-Path "//./pipe/dockerDesktopLinuxEngine") } catch {}

if (-not $dockerRunning) {
    Set-Status "Démarrage de Docker..." "Lancement de Docker Desktop" 20
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep 2
        if (Test-Path "//./pipe/dockerDesktopLinuxEngine") { $dockerRunning = $true; break }
        Set-Status "Démarrage de Docker..." "En attente de Docker Desktop... ($([int]($i * 100 / 60))%)" (20 + [int]($i * 20 / 60))
    }
}

if (-not $dockerRunning) {
    Show-Error "Impossible de démarrer Docker. Lance Docker Desktop manuellement."
    exit 1
}

# ── Containers ────────────────────────────────────────────────────
Set-Status "Lancement du serveur..." "Démarrage des containers Docker" 45
Set-Location $exeDir
$composeOk = $false
for ($i = 0; $i -lt 30; $i++) {
    $composeResult = & docker compose up -d 2>&1
    if ($LASTEXITCODE -eq 0) { $composeOk = $true; break }
    Set-Status "Lancement du serveur..." "En attente du moteur Docker... ($($i+1)/30)" (45 + [int]($i * 5 / 30))
    Start-Sleep 2
}
if (-not $composeOk) {
    Show-Error "Impossible de démarrer les containers :`n$composeResult"
    exit 1
}

# ── Attente port 25565 ────────────────────────────────────────────
Set-Status "Lancement du serveur..." "Démarrage de Minecraft en cours..." 55
for ($i = 0; $i -lt 60; $i++) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try { $tcp.Connect("127.0.0.1", 25565); $tcp.Close(); break } catch {}
    Start-Sleep 2
    Set-Status "Lancement du serveur..." "Démarrage de Minecraft en cours... ($([int]($i * 100 / 60))%)" (55 + [int]($i * 15 / 60))
}

# ── Playit.gg ─────────────────────────────────────────────────────
if ($playitSecret -and (Test-Path $playitExe)) {
    Set-Status "Connexion du tunnel..." "Lancement de Playit.gg" 75
    "secret_key = `"$playitSecret`"" | Set-Content "$exeDir\playit.toml"
    Start-Process $playitExe -WorkingDirectory $exeDir -WindowStyle Hidden
}

# ── Gist ─────────────────────────────────────────────────────────
Set-Status "Finalisation..." "Mise à jour du statut en ligne" 85
Set-GistStatus $true $machineName

# ── Dashboard ────────────────────────────────────────────────────
Set-Status "Finalisation..." "Ouverture du dashboard" 95
for ($i = 0; $i -lt 30; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { break }
    } catch {}
    Start-Sleep 1
}

Set-Status "Prêt !" "Le serveur est en ligne" 100
Start-Sleep 1
$form.Close()
Start-Process "http://localhost:3000"
