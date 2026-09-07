param(
    [int]$Port = 8123,
    [string]$Root = "build/web"
)
# Minimal static file server for the Godot web export (wasm needs proper
# Content-Type; the page must come from http://, not file://).
$Root = Join-Path (Get-Location) $Root
$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript'
    '.mjs'  = 'text/javascript'
    '.wasm' = 'application/wasm'
    '.pck'  = 'application/octet-stream'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.woff2'= 'font/woff2'
}
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Serving $Root -> http://127.0.0.1:$Port/ (Ctrl+C or close window to stop)"
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $rel = $ctx.Request.Url.LocalPath.TrimStart('/')
        if ($rel -eq '') { $rel = 'index.html' }
        $path = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and ($path.StartsWith($Root))) {
            $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
            $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
            $ctx.Response.AddHeader('Cache-Control', 'no-store')
            # Godot 4.2 web builds require cross-origin isolation (COOP+COEP
            # enable SharedArrayBuffer in the browser).
            $ctx.Response.AddHeader('Cross-Origin-Opener-Policy', 'same-origin')
            $ctx.Response.AddHeader('Cross-Origin-Embedder-Policy', 'require-corp')
            $bytes = [IO.File]::ReadAllBytes($path)
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
        $ctx.Response.Close()
    }
} finally {
    $listener.Stop()
}
