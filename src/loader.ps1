# Data layer for Workshop Infrastructure UI.
# No Windows Forms code lives here, so tests can dot-source this file without opening a window.
# Everything is read-only: files are read as text and nothing is executed or written.

$script:Sections = @('Tareas', 'Agentes', 'Skills', 'Documentos', 'Aplicaciones', 'Clientes IA', 'Asistentes')
$script:TypeLabels = @{
    'Tareas' = 'Tarea'
    'Agentes' = 'Agente'
    'Skills' = 'Skill'
    'Documentos' = 'Documento'
    'Aplicaciones' = 'Aplicación'
    'Clientes IA' = 'Guía de cliente IA'
    'Asistentes' = 'Asistente personal'
}

# Folders that are generated, vendored or private, and file names that may hold secrets.
$script:ExcludedFolderPattern = '\\(vendor|node_modules|\.venv|\.git|\.claude|\.codex|\.gemini|clients\\\.codex|clients\\\.agents)(\\|$)'
$script:ExcludedNamePattern = '^(\.env.*|auth\.json|\.credentials\.json|settings\.local\.json|.*(secret|token|credential).*\.(json|txt|ya?ml|ini|xml|config|toml)|.*\.(key|pem|pfx|p12))$'

function Test-ExcludedPath([string]$Path) {
    if (-not $Path) { return $true }
    if ($Path -match $script:ExcludedFolderPattern) { return $true }
    return ([System.IO.Path]::GetFileName($Path) -match $script:ExcludedNamePattern)
}

# True when the path, or any folder between it and the root, is a junction or symbolic link.
function Test-LinkedPath([string]$Path, [string]$Root) {
    $rootPath = $Root.TrimEnd('\')
    $current = $Path
    while ($current -and $current.Length -gt $rootPath.Length) {
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $true }
        } catch { return $false }
        $current = Split-Path -Parent $current
    }
    return $false
}

function Test-InsideRoot([string]$Path, [string]$Root) {
    return [bool]($Path -and $Path.StartsWith($Root.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase))
}

# A path the app may list: inside the workspace, not excluded, not reached through a junction or link.
function Test-AllowedPath([string]$Path, [string]$WorkshopRoot) {
    if (-not (Test-InsideRoot $Path $WorkshopRoot)) { return $false }
    if (Test-ExcludedPath $Path) { return $false }
    return (-not (Test-LinkedPath $Path $WorkshopRoot))
}

function Read-TextFile([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Remove-Diacritics([string]$Text) {
    if (-not $Text) { return '' }
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = [System.Text.StringBuilder]::new($normalized.Length)
    foreach ($char in $normalized.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }
    return $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
}

# Turns a Markdown table cell into plain text: links become their label, code ticks and bold marks go.
function ConvertTo-PlainText([string]$Text) {
    if (-not $Text) { return '' }
    $plain = [regex]::Replace($Text, '\[([^\]]+)\]\([^)]*\)', '$1')
    $plain = $plain -replace '`', '' -replace '\*\*', ''
    return $plain.Trim()
}

function Get-Title([string]$Text, [string]$Fallback) {
    $match = [regex]::Match([regex]::Replace($Text, '(?ms)^```.*?^```', ''), '(?m)^#\s+(.+?)\s*$')
    if ($match.Success) { return (ConvertTo-PlainText $match.Groups[1].Value) }
    return $Fallback
}

# Reads a field from the YAML front matter only (the block between the first two --- lines).
function Get-Field([string]$Text, [string]$Name) {
    $frontMatter = [regex]::Match($Text, '(?s)\A﻿?---\r?\n(.*?)\r?\n---')
    if (-not $frontMatter.Success) { return '' }
    $pattern = '(?m)^' + [regex]::Escape($Name) + ':[ \t]*(?:"([^"]*)"|''([^'']*)''|([^\r\n]+?))[ \t]*$'
    $match = [regex]::Match($frontMatter.Groups[1].Value, $pattern)
    if (-not $match.Success) { return '' }
    foreach ($group in 1..3) {
        if ($match.Groups[$group].Success) {
            $value = $match.Groups[$group].Value.Trim()
            if ($value -in @('>', '|', '>-', '|-')) { return '' }
            return $value
        }
    }
    return ''
}

function Get-FirstParagraph([string]$Text, [string]$Heading) {
    $section = [regex]::Match($Text, '(?ms)^##\s+(?:\d+\.\s*)?' + [regex]::Escape($Heading) + '\s*\r?\n(.*?)(?=^##\s|\z)')
    if (-not $section.Success) { return '' }
    $paragraph = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($section.Groups[1].Value -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) {
            if ($paragraph.Count -gt 0) { break }
            continue
        }
        if ($trimmed.StartsWith('- ') -or $trimmed.StartsWith('|') -or $trimmed.StartsWith('```')) { break }
        $paragraph.Add($trimmed)
    }
    return (ConvertTo-PlainText ($paragraph -join ' '))
}

# A short summary for documents that have no catalogue row: a known section, else the first prose line.
function Get-DocumentSummary([string]$Text) {
    foreach ($heading in @('Purpose', 'Objective', 'Overview', 'Goal', 'Summary')) {
        $paragraph = Get-FirstParagraph $Text $heading
        if ($paragraph) { return $paragraph }
    }
    $body = [regex]::Replace($Text, '(?s)\A﻿?---\r?\n.*?\r?\n---\r?\n', '')
    $body = [regex]::Replace($body, '(?ms)^```.*?^```', '')
    foreach ($paragraph in [regex]::Split($body, '(?:\r?\n){2,}')) {
        $lines = @($paragraph -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($lines.Count -eq 0) { continue }
        if ($lines[0] -match '^(#|\||>|---|[-*+]\s|\d+\.\s|Status:|Last checked:|<)') { continue }
        $summary = ConvertTo-PlainText ($lines -join ' ')
        if ($summary.Length -gt 400) { $summary = $summary.Substring(0, 397).TrimEnd() + '…' }
        return $summary
    }
    return ''
}

function Get-RelativeWorkshopPath([string]$Path, [string]$WorkshopRoot) {
    if ($WorkshopRoot -and $Path.StartsWith($WorkshopRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($WorkshopRoot.TrimEnd('\').Length + 1)
    }
    return $Path
}

# Task status: active, waiting (active but starts only after another task), completed, retired, superseded, other.
function Get-TaskState([string]$Status) {
    if ($Status -match '^\s*active') {
        if ($Status -match 'starts only after') { return 'waiting' }
        return 'active'
    }
    foreach ($state in @('completed', 'retired', 'superseded')) {
        if ($Status -match ('^\s*' + $state)) { return $state }
    }
    return 'other'
}

$script:StatusWords = @{
    'active' = 'Activa'; 'waiting' = 'Activa, en espera'; 'completed' = 'Completada'
    'retired' = 'Retirada'; 'superseded' = 'Sustituida'
}

# Spanish status for display: the state word plus any date or revision in parentheses.
function Get-StatusLabel([string]$Status) {
    if (-not $Status) { return '' }
    $state = Get-TaskState $Status
    if (-not $script:StatusWords.ContainsKey($state)) { return $Status }
    $detail = [regex]::Match(($Status -split ';')[0], '\(([^)]*)\)')
    if ($detail.Success) { return ('{0} ({1})' -f $script:StatusWords[$state], $detail.Groups[1].Value) }
    return $script:StatusWords[$state]
}

# Copy is pasted as-is into an AI client or terminal; Hint explains where. An empty Copy disables the button.
function Get-Usage([string]$Section, [string]$Name, [string]$RelativePath, [string]$Command, [string]$Status) {
    $copy = "Lee el documento $RelativePath"
    $hint = 'Pégalo en tu cliente de IA para que lo use como contexto, o pulsa «Abrir documento» para leerlo.'
    switch ($Section) {
        'Tareas' {
            $state = Get-TaskState $Status
            if ($state -eq 'active') {
                $copy = "Ejecuta la tarea en $RelativePath"
                $hint = 'Pégalo en tu cliente de IA (Claude Code, Codex…) abierto en la carpeta workshop. La tarea se detiene en cada aprobación.'
            } elseif ($state -eq 'waiting') {
                $copy = "Ejecuta la tarea en $RelativePath"
                $hint = 'En espera: empieza solo cuando termine la tarea de la que depende. Comprueba su estado antes de ejecutarla.'
            } else {
                $copy = ''
                $hint = ('No ejecutar: tarea {0}. Se conserva como registro; ábrela solo para consultarla.' -f (Get-StatusLabel $Status).ToLowerInvariant())
            }
        }
        'Agentes' {
            $copy = "Usa el agente $Name para "
            $hint = 'Pégalo en Claude Code y completa la frase con lo que necesitas.'
        }
        'Skills' {
            $copy = "/$Name"
            $hint = "Escríbelo en Claude Code. En Codex CLI escribe `$$Name."
        }
        'Asistentes' {
            $copy = "claude --agent $Name"
            $hint = 'Escríbelo en una terminal abierta en la carpeta workshop.'
        }
        'Aplicaciones' {
            if ($Command) {
                $copy = $Command
                $hint = ('Escríbelo tú en una terminal dentro de applications\{0}. Esta ventana no inicia aplicaciones.' -f $Name)
            } else {
                $copy = "Lee las instrucciones en $RelativePath"
            }
        }
    }
    return [pscustomobject]@{ Copy = $copy; Hint = $hint }
}

function New-Resource {
    param(
        [string]$Section, [string]$Name, [string]$Title, [string]$Description, [string]$Status,
        [string]$Area, [string]$Path, [string]$WorkshopRoot, [string]$Command = ''
    )
    $relative = Get-RelativeWorkshopPath $Path $WorkshopRoot
    $modified = [datetime]::MinValue
    if ($Path -and (Test-Path -LiteralPath $Path)) { $modified = (Get-Item -LiteralPath $Path).LastWriteTime }
    if (-not $Title) { $Title = $Name }
    $typeLabel = $script:TypeLabels[$Section]
    $usage = Get-Usage $Section $Name $relative $Command $Status
    return [pscustomobject]@{
        Section = $Section
        TypeLabel = $typeLabel
        Name = $Name
        Title = $Title
        Description = $Description
        Status = $Status
        Area = $Area
        Path = $Path
        RelativePath = $relative
        Usage = $usage.Copy
        UsageHint = $usage.Hint
        Modified = $modified
        SearchText = Remove-Diacritics ((@($Name, $Title, $Description, $Area, $Status, $typeLabel, $relative) -join ' '))
    }
}

# Reads catalogue rows. Agents and skills: | Area | [name](link) | use | ... ; tasks: | [name](link) | status | purpose | ...
function ConvertFrom-CatalogueTable([string]$Text, [string]$Section) {
    $rows = [System.Collections.Generic.List[object]]::new()
    if ($Section -eq 'Tareas') {
        $pattern = '(?m)^\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|'
        foreach ($match in [regex]::Matches($Text, $pattern)) {
            $rows.Add([pscustomobject]@{
                Name = $match.Groups[1].Value.Trim(); Link = $match.Groups[2].Value
                Status = ConvertTo-PlainText $match.Groups[3].Value; Use = ConvertTo-PlainText $match.Groups[4].Value; Area = ''
            })
        }
    } else {
        $pattern = '(?m)^\|\s*([^|\[]+?)\s*\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*([^|]+?)\s*\|'
        foreach ($match in [regex]::Matches($Text, $pattern)) {
            $rows.Add([pscustomobject]@{
                Area = $match.Groups[1].Value.Trim(); Name = $match.Groups[2].Value.Trim(); Link = $match.Groups[3].Value
                Use = ConvertTo-PlainText $match.Groups[4].Value; Status = ''
            })
        }
    }
    return ,$rows
}

# Resolves a relative catalogue link. Returns '' for links that are absolute, use a scheme or cannot be resolved.
function Resolve-Link([string]$BaseFolder, [string]$Link) {
    $clean = ([System.Uri]::UnescapeDataString((($Link.Trim() -split '#')[0]))) -replace '/', '\'
    if (-not $clean -or $clean.Contains(':') -or $clean.StartsWith('\')) { return '' }
    try { return [System.IO.Path]::GetFullPath((Join-Path $BaseFolder $clean)) } catch { return '' }
}

function Get-DiskCatalogueFiles([string]$InfraRoot, [string]$Section) {
    switch ($Section) {
        'Tareas' {
            $folder = Join-Path $InfraRoot 'tasks'
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return @() }
            return @(Get-ChildItem -LiteralPath $folder -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' })
        }
        'Agentes' {
            $folder = Join-Path $InfraRoot 'agents'
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return @() }
            return @(Get-ChildItem -LiteralPath $folder -File -Filter '*.md' -Recurse |
                Where-Object { $_.FullName -notmatch '\\personal-assistants\\' -and $_.Name -ne 'README.md' })
        }
        'Skills' {
            $folder = Join-Path $InfraRoot 'skills'
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return @() }
            return @(Get-ChildItem -LiteralPath $folder -Directory | ForEach-Object { Join-Path $_.FullName 'SKILL.md' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Item -LiteralPath $_ })
        }
    }
    return @()
}

function Get-DiskName([System.IO.FileInfo]$File, [string]$Section) {
    if ($Section -eq 'Skills') { return $File.Directory.Name }
    return $File.BaseName
}

# Catalogue rows are the source of truth; files on disk are a fallback and a consistency check.
function Get-CatalogueResources([string]$InfraRoot, [string]$WorkshopRoot, [string]$Section, $Warnings) {
    $catalogueName = @{ 'Tareas' = 'tasks.md'; 'Agentes' = 'agents.md'; 'Skills' = 'skills.md' }[$Section]
    $cataloguePath = Join-Path $InfraRoot ('docs\catalogues\' + $catalogueName)
    $items = [System.Collections.Generic.List[object]]::new()
    $diskFiles = @(Get-DiskCatalogueFiles $InfraRoot $Section | Where-Object { Test-AllowedPath $_.FullName $WorkshopRoot })
    $listed = @{}

    if (Test-Path -LiteralPath $cataloguePath -PathType Leaf) {
        $rows = ConvertFrom-CatalogueTable (Read-TextFile $cataloguePath) $Section
        foreach ($row in $rows) {
            $path = Resolve-Link (Split-Path -Parent $cataloguePath) $row.Link
            if (-not $path -or -not (Test-AllowedPath $path $WorkshopRoot)) {
                $Warnings.Add("El catálogo $catalogueName cita '$($row.Name)' con un enlace no válido o fuera del Workshop; se omite.")
                continue
            }
            $listed[$path.ToLowerInvariant()] = $true
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $Warnings.Add("El catálogo $catalogueName cita '$($row.Name)', pero su archivo no existe.")
                continue
            }
            $title = $row.Name
            if ($Section -eq 'Tareas') {
                try { $title = Get-Title (Read-TextFile $path) $row.Name } catch { $title = $row.Name }
                $title = $title -replace '^TASK PROMPT\s*[—:-]+\s*', ''
            }
            $items.Add((New-Resource -Section $Section -Name $row.Name -Title $title -Description $row.Use `
                -Status $row.Status -Area $row.Area -Path $path -WorkshopRoot $WorkshopRoot))
        }
    } else {
        $Warnings.Add("No se encontró el catálogo $catalogueName; se muestran los archivos encontrados en disco.")
    }

    foreach ($file in $diskFiles) {
        if ($listed.ContainsKey($file.FullName.ToLowerInvariant())) { continue }
        $name = Get-DiskName $file $Section
        $description = ''
        $status = ''
        try {
            $body = Read-TextFile $file.FullName
            $description = Get-Field $body 'description'
            if (-not $description) { $description = Get-DocumentSummary $body }
            $statusMatch = [regex]::Match($body, '(?m)^Status:\s*(.+?)\s*$')
            if ($statusMatch.Success) { $status = $statusMatch.Groups[1].Value.Trim() }
        } catch {
            $description = 'No se pudo leer el archivo. Comprueba los permisos y pulsa Actualizar.'
        }
        if (Test-Path -LiteralPath $cataloguePath -PathType Leaf) {
            $Warnings.Add("'$name' existe en disco pero no figura en el catálogo $catalogueName.")
        }
        $items.Add((New-Resource -Section $Section -Name $name -Description $description -Status $status `
            -Area 'Sin catálogo' -Path $file.FullName -WorkshopRoot $WorkshopRoot))
    }
    return $items
}

function Get-DocumentArea([string]$RelativePath) {
    $folder = Split-Path -Parent $RelativePath
    if (-not $folder) { return 'Workshop' }
    $folder = $folder -replace '\\', '/'
    if ($folder -match '^applications/([^/]+)') { return $Matches[1] }
    if ($folder -match '^infra/docs/projects') { return 'infra/docs/projects' }
    return $folder
}

function Get-DocumentResources([string]$InfraRoot, [string]$WorkshopRoot, [string]$ContextText, $Warnings) {
    $files = [System.Collections.Generic.List[string]]::new()
    $contextFile = Join-Path $WorkshopRoot 'WORKSHOP-CONTEXT.md'
    if (Test-Path -LiteralPath $contextFile -PathType Leaf) { $files.Add($contextFile) }
    foreach ($name in @('README.md', 'SECURITY.md')) {
        $path = Join-Path $InfraRoot $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $files.Add($path) }
    }
    $docsFolder = Join-Path $InfraRoot 'docs'
    if (Test-Path -LiteralPath $docsFolder -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $docsFolder -File -Filter '*.md' -Recurse) { $files.Add($file.FullName) }
        if ($ContextText) {
            foreach ($file in Get-ChildItem -LiteralPath $docsFolder -File -Filter '*.md') {
                if ($ContextText.IndexOf($file.Name, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    $Warnings.Add("El documento infra/docs/$($file.Name) no figura en el mapa WORKSHOP-CONTEXT.md.")
                }
            }
        }
    }
    $applications = Join-Path $WorkshopRoot 'applications'
    if (Test-Path -LiteralPath $applications -PathType Container) {
        foreach ($app in Get-ChildItem -LiteralPath $applications -Directory) {
            $appDocs = Join-Path $app.FullName 'docs'
            if (Test-Path -LiteralPath $appDocs -PathType Container) {
                foreach ($file in Get-ChildItem -LiteralPath $appDocs -File -Filter '*.md') { $files.Add($file.FullName) }
            }
        }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $files) {
        if (-not (Test-AllowedPath $path $WorkshopRoot)) { continue }
        $relative = Get-RelativeWorkshopPath $path $WorkshopRoot
        $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $title = $name
        $description = ''
        try {
            $body = Read-TextFile $path
            $title = Get-Title $body $name
            $description = Get-DocumentSummary $body
        } catch {
            $description = 'No se pudo leer el archivo. Comprueba los permisos y pulsa Actualizar.'
        }
        $items.Add((New-Resource -Section 'Documentos' -Name $name -Title $title -Description $description `
            -Area (Get-DocumentArea $relative) -Path $path -WorkshopRoot $WorkshopRoot))
    }
    return $items
}

# Applications come from the table in WORKSHOP-CONTEXT.md section 2; folders missing from it are still shown.
function Get-ApplicationResources([string]$WorkshopRoot, [string]$ContextText, $Warnings) {
    $items = [System.Collections.Generic.List[object]]::new()
    $applications = Join-Path $WorkshopRoot 'applications'
    $rows = @{}
    $summaries = @{}
    if ($ContextText) {
        $table = [regex]::Match($ContextText, '(?ms)^\|\s*Application\s*\|.*?(?=^\s*$|\z)')
        if ($table.Success) {
            foreach ($match in [regex]::Matches($table.Value, '(?m)^\|\s*([A-Za-z0-9._-]+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|')) {
                $name = $match.Groups[1].Value
                if ($name -eq 'Application') { continue }
                $rows[$name.ToLowerInvariant()] = [pscustomobject]@{
                    Name = $name; Stack = ConvertTo-PlainText $match.Groups[2].Value
                    Run = ConvertTo-PlainText $match.Groups[3].Value; Rules = ConvertTo-PlainText $match.Groups[4].Value
                }
            }
        }
        foreach ($match in [regex]::Matches($ContextText, '(?m)^[│ ]*[├└]──\s+([A-Za-z0-9._-]+)/\s{2,}(.+?)\s*$')) {
            $summaries[$match.Groups[1].Value.ToLowerInvariant()] = $match.Groups[2].Value.Trim()
        }
    }
    if (-not (Test-Path -LiteralPath $applications -PathType Container)) { return $items }

    foreach ($folder in Get-ChildItem -LiteralPath $applications -Directory) {
        if (-not (Test-AllowedPath $folder.FullName $WorkshopRoot)) { continue }
        $key = $folder.Name.ToLowerInvariant()
        $path = $folder.FullName
        foreach ($candidate in @('README.md', 'AGENTS.md', 'CLAUDE.md')) {
            $file = Join-Path $folder.FullName $candidate
            if (Test-Path -LiteralPath $file -PathType Leaf) { $path = $file; break }
        }
        $row = $rows[$key]
        $description = $summaries[$key]
        if (-not $description -and $path -ne $folder.FullName) {
            try { $description = Get-DocumentSummary (Read-TextFile $path) } catch { $description = '' }
        }
        $stack = ''
        $command = ''
        if ($row) {
            $stack = $row.Stack
            $command = $row.Run
            if ($description) { $description = "$description`r`n`r`nTecnología: $stack" } else { $description = "Tecnología: $stack" }
        } elseif ($ContextText) {
            $Warnings.Add("La aplicación '$($folder.Name)' no figura en la tabla de aplicaciones de WORKSHOP-CONTEXT.md.")
        }
        $items.Add((New-Resource -Section 'Aplicaciones' -Name $folder.Name -Description $description -Area $stack `
            -Path $path -WorkshopRoot $WorkshopRoot -Command $command))
    }
    return $items
}

function Get-SimpleFolderResources([string]$InfraRoot, [string]$WorkshopRoot, [string]$Section) {
    $items = [System.Collections.Generic.List[object]]::new()
    $files = @()
    if ($Section -eq 'Clientes IA') {
        $folder = Join-Path $InfraRoot 'clients'
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $folder -Directory | Where-Object { -not $_.Name.StartsWith('.') } |
                ForEach-Object { Join-Path $_.FullName 'README.md' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Item -LiteralPath $_ })
        }
    } else {
        $folder = Join-Path $InfraRoot 'agents\personal-assistants'
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' })
        }
    }
    foreach ($file in $files) {
        if (-not (Test-AllowedPath $file.FullName $WorkshopRoot)) { continue }
        $name = $file.BaseName
        if ($Section -eq 'Clientes IA') { $name = $file.Directory.Name }
        $title = $name
        $description = ''
        try {
            $body = Read-TextFile $file.FullName
            if ($Section -eq 'Clientes IA') {
                $title = Get-Title $body $name
                $description = Get-DocumentSummary $body
            } else {
                $description = Get-Field $body 'description'
                if (-not $description) { $description = Get-DocumentSummary $body }
            }
        } catch {
            $description = 'No se pudo leer el archivo. Comprueba los permisos y pulsa Actualizar.'
        }
        $items.Add((New-Resource -Section $Section -Name $name -Title $title -Description $description `
            -Path $file.FullName -WorkshopRoot $WorkshopRoot))
    }
    return $items
}

function Test-ActiveTask($Resource) {
    return ($Resource.Section -eq 'Tareas' -and (Get-TaskState $Resource.Status) -in @('active', 'waiting'))
}

# Loads every resource type. Returns items, warnings and the folders used.
function Get-WorkshopData([string]$InfraRoot) {
    $InfraRoot = [System.IO.Path]::GetFullPath($InfraRoot).TrimEnd('\')
    $workshopRoot = Split-Path -Parent $InfraRoot
    $warnings = [System.Collections.Generic.List[string]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    $contextText = ''
    $contextFile = Join-Path $workshopRoot 'WORKSHOP-CONTEXT.md'
    if (Test-Path -LiteralPath $contextFile -PathType Leaf) {
        $contextText = Read-TextFile $contextFile
    } else {
        $warnings.Add('No se encontró WORKSHOP-CONTEXT.md junto a la carpeta infra; las aplicaciones se leen solo del disco.')
    }

    foreach ($section in @('Tareas', 'Agentes', 'Skills')) {
        foreach ($item in Get-CatalogueResources $InfraRoot $workshopRoot $section $warnings) { $items.Add($item) }
    }
    foreach ($item in Get-DocumentResources $InfraRoot $workshopRoot $contextText $warnings) { $items.Add($item) }
    foreach ($item in Get-ApplicationResources $workshopRoot $contextText $warnings) { $items.Add($item) }
    foreach ($section in @('Clientes IA', 'Asistentes')) {
        foreach ($item in Get-SimpleFolderResources $InfraRoot $workshopRoot $section) { $items.Add($item) }
    }
    return [pscustomobject]@{
        InfraRoot = $InfraRoot
        WorkshopRoot = $workshopRoot
        Items = $items
        Warnings = $warnings
    }
}

# Spanish search words mapped to the English stems used in catalogue descriptions (matched as substrings).
$script:SearchSynonyms = @{
    'seguridad' = @('security', 'secret'); 'secretos' = @('secret'); 'revisor' = @('review'); 'revisar' = @('review')
    'revision' = @('review'); 'auditar' = @('audit'); 'auditoria' = @('audit'); 'diseno' = @('design')
    'disenar' = @('design'); 'interfaz' = @('interface', 'ui'); 'pantalla' = @('ui', 'screen'); 'prueba' = @('test')
    'pruebas' = @('test'); 'probar' = @('test'); 'accesibilidad' = @('accessib', 'wcag'); 'teclado' = @('keyboard')
    'errores' = @('error', 'debug'); 'fallo' = @('error', 'fail', 'debug'); 'depurar' = @('debug'); 'riesgo' = @('risk')
    'estrategia' = @('strategy'); 'datos' = @('data'); 'mercado' = @('market'); 'ordenes' = @('order'); 'orden' = @('order')
    'musica' = @('music'); 'cancion' = @('music', 'track'); 'escribir' = @('writ'); 'redactar' = @('writ')
    'traducir' = @('translat'); 'traduccion' = @('translat'); 'planificar' = @('plan'); 'idea' = @('idea')
    'documentacion' = @('doc'); 'rendimiento' = @('performance'); 'dependencias' = @('dependenc'); 'licencia' = @('license')
    'precio' = @('price', 'market', 'candle'); 'precios' = @('price', 'market', 'candle'); 'dinero' = @('capital', 'money', 'risk')
    'operar' = @('trad', 'order'); 'operaciones' = @('trad', 'order'); 'bot' = @('algo', 'bot', 'strateg'); 'notas' = @('note', 'doc')
    'velas' = @('candle'); 'graficos' = @('chart'); 'bolsa' = @('exchange', 'market'); 'agente' = @('agent'); 'agentes' = @('agent')
    'tarea' = @('task'); 'tareas' = @('task'); 'leer' = @('read'); 'voz' = @('aloud', 'voice')
    'activa' = @('active'); 'activas' = @('active'); 'completada' = @('completed'); 'completadas' = @('completed')
    'repositorio' = @('repo'); 'ramas' = @('branch'); 'subir' = @('push'); 'extension' = @('extension')
}

# Every query word (or one of its English equivalents) must appear in the item's name, title, description, area,
# status, type or path.
# Words of three letters or fewer must match a whole word ("ui" must not match "build").
function Test-WordMatch([string]$Text, [string]$Word) {
    if ($Word.Length -le 3) {
        return [regex]::IsMatch($Text, '(?<![\p{L}\p{N}])' + [regex]::Escape($Word) + '(?![\p{L}\p{N}])')
    }
    return ($Text.IndexOf($Word, [System.StringComparison]::Ordinal) -ge 0)
}

$script:LastQuery = $null
$script:LastWords = @()
function Test-ResourceMatch($Resource, [string]$Query) {
    if ($script:LastQuery -ne $Query) {
        $script:LastQuery = $Query
        $script:LastWords = @((Remove-Diacritics $Query) -split '\s+' | Where-Object { $_ })
    }
    foreach ($word in $script:LastWords) {
        $alternatives = @($word)
        if ($script:SearchSynonyms.ContainsKey($word)) { $alternatives += $script:SearchSynonyms[$word] }
        $found = $false
        foreach ($alternative in $alternatives) {
            if (Test-WordMatch $Resource.SearchText $alternative) { $found = $true; break }
        }
        if (-not $found) { return $false }
    }
    return $true
}

# For a task: the agents, skills and personal assistants its brief mentions by name.
function Get-RelatedResources($Resource, $AllItems) {
    if ($Resource.Section -ne 'Tareas' -or -not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) { return @() }
    $body = Read-TextFile $Resource.Path
    $related = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $AllItems) {
        if ($candidate.Section -notin @('Agentes', 'Skills', 'Asistentes')) { continue }
        if ([regex]::IsMatch($body, '(?<![\w-])' + [regex]::Escape($candidate.Name) + '(?![\w-])', 'IgnoreCase')) { $related.Add($candidate) }
    }
    return ,$related.ToArray()
}
