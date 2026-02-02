# ========================================
# 检查 exe 文件中是否包含 API Key
# ========================================

Write-Host "正在检查安装程序中是否包含敏感信息..." -ForegroundColor Cyan
Write-Host ""

$exePath = "build\windows\x64\runner\Release\xinghe_new.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "❌ 未找到 exe 文件: $exePath" -ForegroundColor Red
    exit 1
}

Write-Host "📂 检查文件: $exePath" -ForegroundColor Yellow
Write-Host ""

# 读取 exe 文件内容
$content = Get-Content $exePath -Encoding Byte -Raw
$text = [System.Text.Encoding]::ASCII.GetString($content)

# 搜索常见的 API Key 特征
$patterns = @(
    "sk-[a-zA-Z0-9]{20,}",           # OpenAI Key
    "mj_[a-zA-Z0-9]{20,}",           # Midjourney Key  
    "AIza[a-zA-Z0-9]{20,}",          # Google API Key
    "gsk_[a-zA-Z0-9]{20,}",          # Gemini Key
    "Bearer sk-",                     # Authorization header
    "api\.openai\.com",              # OpenAI URL
    "api\.midjourney\.com"           # Midjourney URL
)

$found = $false

foreach ($pattern in $patterns) {
    if ($text -match $pattern) {
        Write-Host "⚠️  发现可疑内容: $pattern" -ForegroundColor Yellow
        $found = $true
        
        # 显示匹配的内容（前50个字符）
        $matches = [regex]::Matches($text, $pattern)
        foreach ($match in $matches | Select-Object -First 3) {
            $context = $text.Substring([Math]::Max(0, $match.Index - 20), [Math]::Min(70, $text.Length - $match.Index + 20))
            Write-Host "   内容片段: $($context.Replace("`n", " ").Replace("`r", ""))" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

if (-not $found) {
    Write-Host "✅ 未发现明显的 API Key 特征" -ForegroundColor Green
    Write-Host ""
    Write-Host "说明：" -ForegroundColor Cyan
    Write-Host "  - exe 中没有发现常见的 API Key 格式" -ForegroundColor White
    Write-Host "  - API Key 可能存储在 SecureStorage（加密）" -ForegroundColor White
    Write-Host "  - 用户需要自己配置 Key" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "⚠️  警告：发现可疑内容" -ForegroundColor Yellow
    Write-Host "可能是文档、注释或示例代码" -ForegroundColor Gray
}

Write-Host ""
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
