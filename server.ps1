param(
  [int]$Port = 4173
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

$MimeTypes = @{
  ".html" = "text/html; charset=utf-8"
  ".css" = "text/css; charset=utf-8"
  ".js" = "application/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png" = "image/png"
  ".jpg" = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".svg" = "image/svg+xml"
  ".pdf" = "application/pdf"
  ".xlsx" = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
}

function New-HttpResponseBytes([int]$StatusCode, [string]$StatusText, [string]$ContentType, [byte[]]$Body, [string]$CacheControl = "no-store") {
  $headers = @(
    "HTTP/1.1 $StatusCode $StatusText"
    "Content-Type: $ContentType"
    "Content-Length: $($Body.Length)"
    "Cache-Control: $CacheControl"
    "Access-Control-Allow-Origin: *"
    "Connection: close"
    ""
    ""
  ) -join "`r`n"

  $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headers)
  $response = New-Object byte[] ($headerBytes.Length + $Body.Length)
  [Array]::Copy($headerBytes, 0, $response, 0, $headerBytes.Length)
  [Array]::Copy($Body, 0, $response, $headerBytes.Length, $Body.Length)
  return $response
}

function New-JsonResponse([int]$StatusCode, [string]$StatusText, $Payload) {
  $json = $Payload | ConvertTo-Json -Depth 8 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  return New-HttpResponseBytes $StatusCode $StatusText "application/json; charset=utf-8" $bytes
}

function Append-JsonLine([string]$FileName, $Payload) {
  $record = [ordered]@{
    id = [guid]::NewGuid().ToString()
    receivedAt = (Get-Date).ToUniversalTime().ToString("o")
  }

  foreach ($property in $Payload.PSObject.Properties) {
    $record[$property.Name] = $property.Value
  }

  $line = ($record | ConvertTo-Json -Depth 8 -Compress)
  Add-Content -Path (Join-Path $DataDir $FileName) -Value $line -Encoding UTF8
  return $record
}

function Read-Request($Stream) {
  $buffer = New-Object byte[] 8192
  $memory = New-Object System.IO.MemoryStream
  $headerEnd = -1

  while ($headerEnd -lt 0) {
    $read = $Stream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) { return $null }
    $memory.Write($buffer, 0, $read)
    $rawHeadProbe = [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
    $headerEnd = $rawHeadProbe.IndexOf("`r`n`r`n")
  }

  $initialBytes = $memory.ToArray()
  $raw = [System.Text.Encoding]::UTF8.GetString($initialBytes)
  $parts = $raw -split "`r`n`r`n", 2
  $head = $parts[0]
  $lines = $head -split "`r`n"
  $requestLine = $lines[0] -split " "

  if ($requestLine.Count -lt 2) { return $null }

  $headers = @{}
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $idx = $lines[$i].IndexOf(":")
    if ($idx -gt 0) {
      $name = $lines[$i].Substring(0, $idx).Trim().ToLowerInvariant()
      $value = $lines[$i].Substring($idx + 1).Trim()
      $headers[$name] = $value
    }
  }

  $contentLength = if ($headers.ContainsKey("content-length")) { [int]$headers["content-length"] } else { 0 }
  $bodyStart = $headerEnd + 4
  $currentBodyLength = $initialBytes.Length - $bodyStart

  while ($currentBodyLength -lt $contentLength) {
    $read = $Stream.Read($buffer, 0, [Math]::Min($buffer.Length, $contentLength - $currentBodyLength))
    if ($read -le 0) { break }
    $memory.Write($buffer, 0, $read)
    $currentBodyLength += $read
  }

  $allBytes = $memory.ToArray()
  $body = if ($contentLength -gt 0) {
    [System.Text.Encoding]::UTF8.GetString($allBytes, $bodyStart, [Math]::Min($contentLength, $allBytes.Length - $bodyStart))
  }
  else {
    ""
  }

  return [pscustomobject]@{
    Method = $requestLine[0]
    Path = ($requestLine[1] -split "\?")[0]
    Headers = $headers
    Body = $body
  }
}

function Handle-Api($Request) {
  try {
    if ($Request.Method -ne "POST") {
      return New-JsonResponse 405 "Method Not Allowed" @{ ok = $false; error = "Method not allowed" }
    }

    $payload = if ($Request.Body) { $Request.Body | ConvertFrom-Json } else { [pscustomobject]@{} }

    if ($Request.Path -eq "/api/leads") {
      $name = ([string]$payload.name).Trim()
      $email = ([string]$payload.email).Trim().ToLowerInvariant()
      $interest = ([string]$payload.interest).Trim()

      if (-not $name -or -not $email -or -not $interest) {
        return New-JsonResponse 400 "Bad Request" @{ ok = $false; error = "Missing required lead fields" }
      }

      if ($email -notmatch "^[^\s@]+@[^\s@]+\.[^\s@]+$") {
        return New-JsonResponse 400 "Bad Request" @{ ok = $false; error = "Invalid email" }
      }

      $lead = Append-JsonLine "leads.jsonl" ([pscustomobject]@{
        name = $name
        email = $email
        interest = $interest
        message = ([string]$payload.message).Trim()
        sessionId = ([string]$payload.sessionId).Trim()
      })
      return New-JsonResponse 201 "Created" @{ ok = $true; id = $lead.id }
    }

    if ($Request.Path -eq "/api/analytics") {
      Append-JsonLine "analytics.jsonl" ([pscustomobject]@{
        event = ([string]$payload.event)
        path = ([string]$payload.path)
        title = ([string]$payload.title)
        sessionId = ([string]$payload.sessionId)
        timestamp = ([string]$payload.timestamp)
        label = ([string]$payload.label)
        href = ([string]$payload.href)
        referrer = ([string]$payload.referrer)
        viewport = ([string]$payload.viewport)
        interest = ([string]$payload.interest)
      }) | Out-Null
      return New-JsonResponse 202 "Accepted" @{ ok = $true }
    }

    return New-JsonResponse 404 "Not Found" @{ ok = $false; error = "Endpoint not found" }
  }
  catch {
    return New-JsonResponse 400 "Bad Request" @{ ok = $false; error = $_.Exception.Message }
  }
}

function Serve-Static($Request) {
  $path = [System.Uri]::UnescapeDataString($Request.Path)
  if ($path -eq "/") { $path = "/index.html" }

  $relative = $path.TrimStart("/") -replace "/", [System.IO.Path]::DirectorySeparatorChar
  $filePath = [System.IO.Path]::GetFullPath((Join-Path $Root $relative))
  $rootFull = [System.IO.Path]::GetFullPath($Root)

  if (-not $filePath.StartsWith($rootFull)) {
    return New-JsonResponse 403 "Forbidden" @{ ok = $false; error = "Forbidden" }
  }

  if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
    $notFound = [System.Text.Encoding]::UTF8.GetBytes("Not found")
    return New-HttpResponseBytes 404 "Not Found" "text/plain; charset=utf-8" $notFound
  }

  $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
  $contentType = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { "application/octet-stream" }
  $cache = if ($ext -eq ".html") { "no-store" } else { "public, max-age=3600" }
  $bytes = [System.IO.File]::ReadAllBytes($filePath)
  return New-HttpResponseBytes 200 "OK" $contentType $bytes $cache
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "Synetik.IO running at http://localhost:$Port"

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $request = Read-Request $stream
      if ($null -eq $request) { continue }

      if ($request.Path.StartsWith("/api/")) {
        $response = Handle-Api $request
      }
      else {
        $response = Serve-Static $request
      }

      $stream.Write($response, 0, $response.Length)
    }
    finally {
      $client.Close()
    }
  }
}
finally {
  $listener.Stop()
}
