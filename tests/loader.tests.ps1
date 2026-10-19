# Non-UI checks for src/loader.ps1. Run: powershell.exe -NoProfile -File tests\loader.tests.ps1
# Uses the real workspace for count checks and a temporary fixture for exclusions, hostile links and warnings.
param([string]$InfraRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\loader.ps1')

$script:Passed = 0
$script:Failed = [System.Collections.Generic.List[string]]::new()
function Assert([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:Passed++ } else { $script:Failed.Add($Name) }
}

if (-not $InfraRoot) { $InfraRoot = Join-Path $PSScriptRoot '..\..\..\infra' }
$InfraRoot = [System.IO.Path]::GetFullPath($InfraRoot)

# --- Parsing helpers ---
$agentTable = "| Area | Agent | Use it to | Access |`n|---|---|---|---|`n| UI | [ui-designer](../../agents/ui/ui-designer.md) | Visual ``design`` | Edit |"
$rows = ConvertFrom-CatalogueTable $agentTable 'Agentes'
Assert ($rows.Count -eq 1 -and $rows[0].Name -eq 'ui-designer' -and $rows[0].Area -eq 'UI' -and $rows[0].Use -eq 'Visual design') 'agent catalogue row parses'
Assert ((ConvertFrom-CatalogueTable 'no table here' 'Agentes').Count -eq 0) 'empty catalogue returns an empty list'
$taskTable = "| Task | Status | Purpose |`n|---|---|---|`n| [a-task](../../tasks/a-task.md) | active (rev. 2) | Do [it](x.md) |"
$rows = ConvertFrom-CatalogueTable $taskTable 'Tareas'
Assert ($rows.Count -eq 1 -and $rows[0].Status -eq 'active (rev. 2)' -and $rows[0].Use -eq 'Do it') 'task catalogue row parses'
Assert ((Get-Field "---`nname: x`ndescription: ""Hello there""`n---" 'description') -eq 'Hello there') 'front matter description parses'
Assert ((Get-Field "# Doc`n`ndescription: not front matter" 'description') -eq '') 'fields outside front matter are ignored'
Assert ((Get-Field "---`ndescription: >`n  folded`n---" 'description') -eq '') 'folded YAML marker is not shown as a description'
Assert ((Get-Title "``````text`n# not a title`n```````n# Real title" 'x') -eq 'Real title') 'title ignores code fences'
Assert ((Get-DocumentSummary "# Title`n`nStatus: x`n`n- list`n`nFirst real`nparagraph.`n") -eq 'First real paragraph.') 'document summary skips lists and metadata'
Assert ((Remove-Diacritics 'Diseño ÁGIL') -eq 'diseno agil') 'diacritics removed'
Assert ((Resolve-Link 'C:\w\infra\docs\catalogues' 'http://example.com/a.md') -eq '') 'web links rejected'
Assert ((Resolve-Link 'C:\w\infra\docs\catalogues' 'C:\Windows\win.ini') -eq '') 'absolute links rejected'
Assert ((Resolve-Link 'C:\w\infra\docs\catalogues' '../../agents/a%20b.md#x') -eq 'C:\w\infra\agents\a b.md') 'encoded relative link resolves'
Assert ((Get-StatusLabel 'active (rev. 2, 2026-10-18); starts only after X') -eq 'Activa, en espera (rev. 2, 2026-10-18)') 'waiting status label'
Assert ((Get-StatusLabel 'completed (2026-10-17)') -eq 'Completada (2026-10-17)') 'completed status label'

# --- Exclusions ---
foreach ($path in @('C:\w\infra\vendor\x.md', 'C:\w\infra\clients\.codex\agents\a.md', 'C:\w\infra\clients\.agents\skills\s\README.md',
        'C:\w\app\node_modules\p\README.md', 'C:\w\app\.venv\l.md', 'C:\w\app\.env', 'C:\w\app\.env.local', 'C:\w\x\auth.json',
        'C:\w\x\settings.local.json', 'C:\w\x\.credentials.json', 'C:\w\x\id.key', 'C:\w\x\api-token.txt', 'C:\w\x\client_secret.json')) {
    Assert (Test-ExcludedPath $path) "excluded: $path"
}
Assert (-not (Test-ExcludedPath 'C:\w\infra\docs\onboarding.md')) 'normal doc not excluded'
Assert (-not (Test-ExcludedPath 'C:\w\infra\docs\token-optimization-candidate-review.md')) 'Markdown doc with "token" in its name not excluded'

# --- Search ---
Assert (Test-ResourceMatch ([pscustomobject]@{ SearchText = 'build a windows-friendly ui-designer' }) 'ui') 'short word matches a whole word'
Assert (-not (Test-ResourceMatch ([pscustomobject]@{ SearchText = 'build things' }) 'ui')) 'short word does not match inside a word'

# --- Real workspace ---
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$data = Get-WorkshopData $InfraRoot
$elapsed = $timer.ElapsedMilliseconds
Assert ($elapsed -lt 2000) "loads in under 2 s (took $elapsed ms)"

function Get-RowCount([string]$File, [string]$Pattern) {
    return @((Read-TextFile (Join-Path $InfraRoot $File)) -split "`r?`n" | Where-Object { $_ -match $Pattern }).Count
}
$expected = @{
    'Agentes' = Get-RowCount 'docs\catalogues\agents.md' '^\|\s*[^|\[]+\|\s*\[[^\]]+\]\('
    'Skills' = Get-RowCount 'docs\catalogues\skills.md' '^\|\s*[^|\[]+\|\s*\[[^\]]+\]\('
    'Tareas' = Get-RowCount 'docs\catalogues\tasks.md' '^\|\s*\[[^\]]+\]\('
}
foreach ($section in $expected.Keys) {
    $actual = @($data.Items | Where-Object { $_.Section -eq $section -and $_.Area -ne 'Sin catálogo' }).Count
    Assert ($actual -eq $expected[$section]) "$section count matches catalogue (expected $($expected[$section]), got $actual)"
}
foreach ($section in $script:Sections) {
    Assert (@($data.Items | Where-Object { $_.Section -eq $section }).Count -gt 0) "section has items: $section"
}
Assert (@($data.Items | Where-Object { Test-ExcludedPath $_.Path }).Count -eq 0) 'no excluded path is listed'
Assert (@($data.Items | Where-Object { $_.Path -match '\\clients\\\.' }).Count -eq 0) 'generated adapter files are not listed'
Assert (@($data.Items | Where-Object { -not (Test-InsideRoot $_.Path $data.WorkshopRoot) }).Count -eq 0) 'every listed path is inside the workspace'
Assert (@($data.Items | Where-Object { $_.Path -and -not (Test-Path -LiteralPath $_.Path) }).Count -eq 0) 'every listed path exists'

foreach ($skill in @($data.Items | Where-Object { $_.Section -eq 'Skills' })) {
    Assert ($skill.Usage -eq ('/' + $skill.Name) -and $skill.UsageHint.Contains('$' + $skill.Name)) "skill usage: $($skill.Name)"
}
foreach ($task in @($data.Items | Where-Object { $_.Section -eq 'Tareas' })) {
    if (Test-ActiveTask $task) {
        Assert ($task.Usage -like 'Ejecuta la tarea en infra\tasks\*.md') "active task usage: $($task.Name)"
    } else {
        Assert (-not $task.Usage -and $task.UsageHint -like 'No ejecutar:*') "inactive task is not offered to run: $($task.Name)"
    }
    Assert ($task.Title -notmatch '^TASK PROMPT') "task title cleaned: $($task.Name)"
    $related = Get-RelatedResources $task $data.Items
    Assert ($related -is [array] -and @($related | Where-Object { $null -eq $_ }).Count -eq 0) "related list has no null entries: $($task.Name)"
}
foreach ($agent in @($data.Items | Where-Object { $_.Section -eq 'Agentes' })) {
    Assert ($agent.Usage -eq "Usa el agente $($agent.Name) para ") "agent usage: $($agent.Name)"
}

$securityReviewer = @($data.Items | Where-Object { $_.Name -eq 'security-reviewer' })[0]
Assert ($null -ne $securityReviewer -and (Test-ResourceMatch $securityReviewer 'seguridad')) 'Spanish search finds security-reviewer'
Assert ($null -ne $securityReviewer -and -not (Test-ResourceMatch $securityReviewer 'seguridad música')) 'all search words must match'
$ui = @($data.Items | Where-Object { $_.Section -eq 'Aplicaciones' -and $_.Name -eq 'workshop-infrastructure-ui' })[0]
Assert ($null -ne $ui -and $ui.Usage -match 'INICIAR\.cmd' -and $ui.UsageHint -match 'no inicia') 'application usage shows its launch command as text'

# --- Fixture: catalogue/disk mismatch, hostile links and secrets ---
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('workshop-ui-test-' + [guid]::NewGuid().ToString('N'))
try {
    $infra = Join-Path $fixture 'infra'
    foreach ($folder in @('tasks', 'agents\ui', 'skills\demo-skill', 'docs\catalogues', 'clients\demo-client', 'clients\.codex', 'agents\personal-assistants')) {
        [void](New-Item -ItemType Directory -Force (Join-Path $infra $folder))
    }
    Set-Content -LiteralPath (Join-Path $fixture 'outside.md') -Encoding UTF8 -Value '# Outside the infra folder'
    Set-Content -LiteralPath (Join-Path $infra 'docs\catalogues\agents.md') -Encoding UTF8 -Value @(
        '| Area | Agent | Use | Access |', '|---|---|---|---|',
        '| UI | [listed](../../agents/ui/listed.md) | Listed agent | RO |',
        '| UI | [missing](../../agents/ui/missing.md) | Missing agent | RO |',
        '| UI | [web](http://example.com/a.md) | Web link | RO |',
        '| UI | [drive](C:\Windows\win.ini) | Absolute link | RO |',
        '| UI | [outside](../../../../outside.md) | Outside link | RO |')
    Set-Content -LiteralPath (Join-Path $infra 'agents\ui\listed.md') -Encoding UTF8 -Value "---`nname: listed`n---"
    Set-Content -LiteralPath (Join-Path $infra 'agents\ui\extra.md') -Encoding UTF8 -Value "---`nname: extra`ndescription: Extra`n---"
    Set-Content -LiteralPath (Join-Path $infra 'skills\demo-skill\SKILL.md') -Encoding UTF8 -Value "---`nname: demo-skill`ndescription: Demo`n---"
    Set-Content -LiteralPath (Join-Path $infra 'clients\demo-client\README.md') -Encoding UTF8 -Value "# Demo client`n`nGuide text."
    Set-Content -LiteralPath (Join-Path $infra 'clients\.codex\README.md') -Encoding UTF8 -Value '# Generated'
    Set-Content -LiteralPath (Join-Path $infra 'clients\demo-client\.env') -Encoding UTF8 -Value 'SECRET=not-read'

    $fixtureData = Get-WorkshopData $infra
    $fixtureWarnings = $fixtureData.Warnings -join "`n"
    Assert ($fixtureWarnings -match "cita 'missing', pero su archivo no existe") 'warns about catalogue row without file'
    Assert ($fixtureWarnings -match "'extra' existe en disco") 'warns about file without catalogue row'
    foreach ($name in @('web', 'drive', 'outside')) {
        Assert ($fixtureWarnings -match "cita '$name' con un enlace no válido") "hostile link skipped with a warning: $name"
    }
    Assert (@($fixtureData.Items | Where-Object { $_.Section -eq 'Agentes' }).Count -eq 2) 'only listed and extra agents loaded'
    Assert ($fixtureWarnings -match 'skills\.md') 'warns about missing skills catalogue and falls back to disk'
    Assert (@($fixtureData.Items | Where-Object { $_.Name -eq 'demo-skill' }).Count -eq 1) 'disk fallback lists the skill'
    Assert (@($fixtureData.Items | Where-Object { $_.Section -eq 'Clientes IA' }).Count -eq 1) 'only real client guides listed'
    Assert (@($fixtureData.Items | Where-Object { $_.Path -match '\.env$|\\\.codex\\' }).Count -eq 0) 'fixture secrets and generated files ignored'

    # A junction inside docs must not be followed.
    $target = Join-Path $fixture 'linked-target'
    [void](New-Item -ItemType Directory -Force $target)
    Set-Content -LiteralPath (Join-Path $target 'leak.md') -Encoding UTF8 -Value '# Leak'
    $junction = Join-Path $infra 'docs\linked'
    $made = $true
    try { [void](New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop) } catch { $made = $false }
    if ($made) {
        $linkedData = Get-WorkshopData $infra
        Assert (@($linkedData.Items | Where-Object { $_.Path -like '*leak.md' }).Count -eq 0) 'files behind a junction are not listed'
        [System.IO.Directory]::Delete($junction)
    } else {
        Write-Output 'NOT CHECKED: junction test (could not create a junction here)'
    }
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

Write-Output ("Passed: {0}  Failed: {1}" -f $script:Passed, $script:Failed.Count)
foreach ($name in $script:Failed) { Write-Output "  FAILED: $name" }
if ($script:Failed.Count -gt 0) { exit 1 }
