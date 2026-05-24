$ErrorActionPreference = "Stop"

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$PORT = 5500

Set-Location $ROOT

Write-Host ""
Write-Host "COBO LitVM Testnet Lab v1.3 rodando em:" -ForegroundColor Green
Write-Host "http://127.0.0.1:$PORT/index.html" -ForegroundColor Cyan
Write-Host ""
Write-Host "NAO FECHE ESTA JANELA. Para parar, pressione CTRL + C." -ForegroundColor Yellow
Write-Host ""

$connections = Get-NetTCPConnection -LocalPort $PORT -ErrorAction SilentlyContinue
if ($connections) {
    $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($pidItem in $pids) {
        try { Stop-Process -Id $pidItem -Force -ErrorAction SilentlyContinue } catch {}
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $PORT)
$listener.Start()

function Get-ContentType($path) {
    switch -Regex ($path) {
        "\.html$" { return "text/html; charset=utf-8" }
        "\.css$"  { return "text/css; charset=utf-8" }
        "\.js$"   { return "application/javascript; charset=utf-8" }
        "\.png$"  { return "image/png" }
        "\.jpg$"  { return "image/jpeg" }
        "\.jpeg$" { return "image/jpeg" }
        "\.md$"   { return "text/plain; charset=utf-8" }
        default   { return "application/octet-stream" }
    }
}

Start-Process "msedge.exe" "http://127.0.0.1:$PORT/index.html"

while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $requestLine = $reader.ReadLine()

        if ([string]::IsNullOrWhiteSpace($requestLine)) {
            $client.Close()
            continue
        }

        $parts = $requestLine.Split(" ")
        $urlPath = $parts[1]

        if ($urlPath -eq "/") { $urlPath = "/index.html" }

        $urlPath = [System.Uri]::UnescapeDataString($urlPath)
        $urlPath = $urlPath.TrimStart("/")
        $filePath = Join-Path $ROOT $urlPath

        if (!(Test-Path $filePath)) {
            $body = [System.Text.Encoding]::UTF8.GetBytes("404 - arquivo nao encontrado: $urlPath")
            $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Write($body, 0, $body.Length)
        } else {
            $body = [System.IO.File]::ReadAllBytes($filePath)
            $ctype = Get-ContentType $filePath
            $header = "HTTP/1.1 200 OK`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Write($body, 0, $body.Length)
            Write-Host "200 OK /$urlPath" -ForegroundColor DarkGreen
        }
    } catch {
        Write-Host "Erro ao servir arquivo: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        $client.Close()
    }
}
