Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:InfraRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\infra'))
$script:Category = 'Tareas'
$script:Resources = @()
$script:SelectedResource = $null

$script:Colors = @{
    Ink = [System.Drawing.Color]::FromArgb(31, 43, 58)
    Muted = [System.Drawing.Color]::FromArgb(99, 112, 128)
    Accent = [System.Drawing.Color]::FromArgb(42, 91, 160)
    SelectedText = [System.Drawing.Color]::FromArgb(42, 91, 160)
    ActionText = [System.Drawing.Color]::White
    Canvas = [System.Drawing.Color]::FromArgb(246, 248, 251)
    Line = [System.Drawing.Color]::FromArgb(221, 227, 234)
    White = [System.Drawing.Color]::White
    SoftBlue = [System.Drawing.Color]::FromArgb(232, 240, 250)
}
if ([System.Windows.Forms.SystemInformation]::HighContrast) {
    $script:Colors.Ink = [System.Drawing.SystemColors]::WindowText
    $script:Colors.Muted = [System.Drawing.SystemColors]::WindowText
    $script:Colors.Accent = [System.Drawing.SystemColors]::Highlight
    $script:Colors.SelectedText = [System.Drawing.SystemColors]::HighlightText
    $script:Colors.ActionText = [System.Drawing.SystemColors]::HighlightText
    $script:Colors.Canvas = [System.Drawing.SystemColors]::Window
    $script:Colors.Line = [System.Drawing.SystemColors]::WindowText
    $script:Colors.White = [System.Drawing.SystemColors]::Window
    $script:Colors.SoftBlue = [System.Drawing.SystemColors]::Highlight
}

function Get-RelativePath([string]$Path) {
    if ($Path.StartsWith($script:InfraRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($script:InfraRoot.Length).TrimStart('\')
    }
    return $Path
}

function Get-Title([string]$Text, [string]$Fallback) {
    $match = [regex]::Match($Text, '(?m)^#\s+(.+?)\s*$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $Fallback
}

function Get-Field([string]$Text, [string]$Name) {
    $pattern = '(?m)^' + [regex]::Escape($Name) + ':\s*(?:"([^"]*)"|''([^'']*)''|(.+))\s*$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return '' }
    foreach ($group in 1..3) {
        if ($match.Groups[$group].Success) { return $match.Groups[$group].Value.Trim() }
    }
    return ''
}

function Get-FirstParagraph([string]$Text, [string]$Heading) {
    $section = [regex]::Match($Text, '(?ms)^##\s+' + [regex]::Escape($Heading) + '\s*\r?\n(.*?)(?=^##\s|\z)')
    if (-not $section.Success) { return '' }
    $lines = @($section.Groups[1].Value -split "`r?`n")
    $paragraph = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) {
            if ($paragraph.Count -gt 0) { break }
            continue
        }
        if ($trimmed.StartsWith('- ') -or $trimmed.StartsWith('|')) { break }
        $paragraph.Add($trimmed)
    }
    return ($paragraph -join ' ')
}

function Read-Resource([System.IO.FileInfo]$File, [string]$Kind) {
    $body = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)
    $title = Get-Title $body $File.BaseName
    $description = ''
    $status = ''
    switch ($Kind) {
        'Tareas' {
            $description = Get-FirstParagraph $body 'Objective'
            if (-not $description) { $description = Get-FirstParagraph $body 'Purpose' }
            $statusMatch = [regex]::Match($body, '(?m)^Status:\s*(.+?)\s*$')
            if ($statusMatch.Success) { $status = $statusMatch.Groups[1].Value.Trim() }
        }
        'Agentes' {
            $description = Get-Field $body 'description'
            $status = 'Agente'
        }
        'Skills' {
            $description = Get-Field $body 'description'
            $status = 'Skill'
        }
        'Clientes' {
            $description = Get-FirstParagraph $body 'Purpose'
            $status = 'Guía'
        }
        default {
            $description = Get-FirstParagraph $body 'Purpose'
            if (-not $description) { $description = Get-FirstParagraph $body 'Overview' }
            $status = 'Documento'
        }
    }
    if (-not $description) {
        $firstText = [regex]::Match($body, '(?m)^(?!#|Status:|---|\s*$)(.{1,400})$')
        if ($firstText.Success) { $description = $firstText.Groups[1].Value.Trim() }
    }
    return [pscustomobject]@{
        Title = $title
        Kind = $Kind
        Status = $status
        Description = $description
        Path = $File.FullName
        RelativePath = Get-RelativePath $File.FullName
    }
}

function Get-ResourceFiles([string]$Kind) {
    $base = switch ($Kind) {
        'Tareas' { Join-Path $script:InfraRoot 'tasks' }
        'Agentes' { Join-Path $script:InfraRoot 'agents' }
        'Skills' { Join-Path $script:InfraRoot 'skills' }
        'Clientes' { Join-Path $script:InfraRoot 'clients' }
        default { Join-Path $script:InfraRoot 'docs' }
    }
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return @() }
    $files = switch ($Kind) {
        'Tareas' { Get-ChildItem -LiteralPath $base -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' } }
        'Agentes' { Get-ChildItem -LiteralPath $base -File -Filter '*.md' -Recurse }
        'Skills' { Get-ChildItem -LiteralPath $base -File -Filter 'SKILL.md' -Recurse }
        'Clientes' { Get-ChildItem -LiteralPath $base -File -Filter 'README.md' -Recurse }
        default {
            @(
                (Join-Path $script:InfraRoot 'docs\onboarding.md'),
                (Join-Path $script:InfraRoot 'SECURITY.md'),
                (Join-Path $script:InfraRoot 'docs\ai-architecture.md'),
                (Join-Path $script:InfraRoot 'docs\workshop.md')
            ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Item -LiteralPath $_ }
        }
    }
    foreach ($file in $files) {
        try {
            Read-Resource $file $Kind
        } catch {
            [pscustomobject]@{
                Title = $file.BaseName
                Kind = $Kind
                Status = 'No se pudo leer'
                Description = 'No se pudo leer el archivo. Comprueba los permisos y vuelve a actualizar la lista.'
                Path = $file.FullName
                RelativePath = Get-RelativePath $file.FullName
            }
        }
    }
}

function Set-Status([string]$Message, [bool]$IsError = $false) {
    $script:StatusLabel.Text = $Message
    if ($IsError -and -not [System.Windows.Forms.SystemInformation]::HighContrast) {
        $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(170, 49, 44)
    } else {
        $script:StatusLabel.ForeColor = $script:Colors.Muted
    }
}

function Show-Details($Resource) {
    $script:SelectedResource = $Resource
    if (-not $Resource) {
        $script:DetailTitle.Text = 'Elige un recurso'
        $script:DetailDescription.Text = 'Selecciona un elemento de la lista para ver su resumen y abrir el documento original.'
        $script:DetailPath.Text = ''
        $script:OpenButton.Enabled = $false
        return
    }
    $script:DetailTitle.Text = $Resource.Title
    $script:DetailDescription.Text = if ($Resource.Description) { $Resource.Description } else { 'Este documento no incluye un resumen breve.' }
    $script:DetailPath.Text = $Resource.RelativePath
    $script:OpenButton.Enabled = Test-Path -LiteralPath $Resource.Path -PathType Leaf
}

function Refresh-List {
    $script:ResourceList.BeginUpdate()
    $script:ResourceList.Items.Clear()
    $script:Resources = @(Get-ResourceFiles $script:Category | Sort-Object Title)
    $query = $script:SearchBox.Text.Trim()
    $statusFilter = [string]$script:StatusFilter.SelectedItem
    $filtered = @($script:Resources | Where-Object {
        $matchesQuery = -not $query -or $_.Title.IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Description.IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        $matchesStatus = $script:Category -ne 'Tareas' -or $statusFilter -eq 'Todos los estados' -or $_.Status -eq 'No se pudo leer' -or $_.Status -like "*$statusFilter*"
        $matchesQuery -and $matchesStatus
    })
    foreach ($resource in $filtered) {
        $item = [System.Windows.Forms.ListViewItem]::new([string]$resource.Title)
        [void]$item.SubItems.Add([string]$resource.Status)
        $item.Tag = $resource
        [void]$script:ResourceList.Items.Add($item)
    }
    $script:ResourceList.EndUpdate()
    Show-Details $null
    if (-not (Test-Path -LiteralPath $script:InfraRoot -PathType Container)) {
        Set-Status 'No se encontró la carpeta infra. Selecciona su ubicación para continuar.' $true
    } elseif ($filtered.Count -eq 0 -and $query) {
        Set-Status 'No hay resultados. Prueba otros términos o limpia la búsqueda.'
    } elseif ($filtered.Count -eq 0) {
        Set-Status 'No se encontraron documentos en esta categoría.'
    } else {
        $unreadable = @($script:Resources | Where-Object { $_.Status -eq 'No se pudo leer' }).Count
        if ($unreadable -gt 0) {
            Set-Status ("{0} elementos · {1} documentos no se pudieron leer" -f $filtered.Count, $unreadable) $true
        } else {
            Set-Status ("{0} elementos · {1} total" -f $filtered.Count, $script:Resources.Count)
        }
    }
}

function Set-Category([string]$Name) {
    $script:Category = $Name
    foreach ($button in $script:NavButtons) {
        $isSelected = $button.Tag -eq $Name
        $button.BackColor = if ($isSelected) { $script:Colors.SoftBlue } else { $script:Colors.White }
        $button.ForeColor = if ($isSelected) { $script:Colors.SelectedText } else { $script:Colors.Ink }
        $button.AccessibleDescription = if ($isSelected) { 'Sección actual' } else { 'Abrir esta sección' }
    }
    $script:CategoryTitle.Text = $Name
    $script:StatusFilter.Visible = ($Name -eq 'Tareas')
    Refresh-List
}

function Open-SelectedFile {
    if (-not $script:SelectedResource -or -not (Test-Path -LiteralPath $script:SelectedResource.Path -PathType Leaf)) {
        Set-Status 'El documento ya no está disponible. Actualiza la lista e inténtalo de nuevo.' $true
        return
    }
    try {
        Start-Process -FilePath $script:SelectedResource.Path -ErrorAction Stop
        Set-Status ("Abriendo {0}" -f $script:SelectedResource.RelativePath)
    } catch {
        Set-Status 'No se pudo abrir el documento. Comprueba que exista una aplicación asociada a archivos Markdown.' $true
    }
}

$script:Form = [System.Windows.Forms.Form]::new()
$script:Form.Text = 'Workshop · Infraestructura'
$script:Form.StartPosition = 'CenterScreen'
$script:Form.Size = [System.Drawing.Size]::new(1120, 760)
$script:Form.MinimumSize = [System.Drawing.Size]::new(900, 600)
$script:Form.BackColor = $script:Colors.Canvas
$script:Form.Font = [System.Drawing.Font]::new('Segoe UI', 10)

$rootLayout = [System.Windows.Forms.TableLayoutPanel]::new()
$rootLayout.Dock = 'Fill'
$rootLayout.ColumnCount = 2
$rootLayout.RowCount = 2
$rootLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute', 205))
$rootLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 100))
$rootLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
$rootLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 34))
$script:Form.Controls.Add($rootLayout)

$sidebar = [System.Windows.Forms.Panel]::new()
$sidebar.Dock = 'Fill'
$sidebar.BackColor = $script:Colors.White
$sidebar.Padding = [System.Windows.Forms.Padding]::new(16, 18, 12, 12)
$rootLayout.Controls.Add($sidebar, 0, 0)
$sidebarTitle = [System.Windows.Forms.Label]::new()
$sidebarTitle.Text = 'Workshop'
$sidebarTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 17)
$sidebarTitle.ForeColor = $script:Colors.Ink
$sidebarTitle.AutoSize = $true
$sidebarTitle.Location = [System.Drawing.Point]::new(16, 17)
$sidebar.Controls.Add($sidebarTitle)
$sidebarSubtitle = [System.Windows.Forms.Label]::new()
$sidebarSubtitle.Text = 'Infraestructura compartida'
$sidebarSubtitle.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$sidebarSubtitle.ForeColor = $script:Colors.Muted
$sidebarSubtitle.AutoSize = $true
$sidebarSubtitle.Location = [System.Drawing.Point]::new(17, 47)
$sidebar.Controls.Add($sidebarSubtitle)

$navPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
$navPanel.FlowDirection = 'TopDown'
$navPanel.WrapContents = $false
$navPanel.Location = [System.Drawing.Point]::new(10, 90)
$navPanel.Size = [System.Drawing.Size]::new(180, 240)
$navPanel.Anchor = 'Top, Left, Right'
$sidebar.Controls.Add($navPanel)
$script:NavButtons = @()
foreach ($name in @('Tareas', 'Agentes', 'Skills', 'Clientes', 'Ayuda')) {
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $name
    $button.Width = 174
    $button.Height = 42
    $button.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 5)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.TextAlign = 'MiddleLeft'
    $button.Padding = [System.Windows.Forms.Padding]::new(12, 0, 0, 0)
    $button.Cursor = 'Hand'
    $button.TabIndex = $script:NavButtons.Count
    $button.AccessibleName = $name
    $button.Tag = $name
    $button.Add_Click({ param($sender, $eventArgs) Set-Category $sender.Tag })
    $script:NavButtons += $button
    $navPanel.Controls.Add($button)
}

$rootLabel = [System.Windows.Forms.Label]::new()
$rootLabel.Text = 'Carpeta infra'
$rootLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 9)
$rootLabel.ForeColor = $script:Colors.Muted
$rootLabel.AutoSize = $true
$rootLabel.Location = [System.Drawing.Point]::new(17, 356)
$sidebar.Controls.Add($rootLabel)
$script:RootPathLabel = [System.Windows.Forms.Label]::new()
$script:RootPathLabel.Text = Get-RelativePath $script:InfraRoot
$script:RootPathLabel.AutoEllipsis = $true
$script:RootPathLabel.Size = [System.Drawing.Size]::new(172, 40)
$script:RootPathLabel.Location = [System.Drawing.Point]::new(17, 378)
$script:RootPathLabel.ForeColor = $script:Colors.Ink
$sidebar.Controls.Add($script:RootPathLabel)
$chooseRootButton = [System.Windows.Forms.Button]::new()
$chooseRootButton.Text = 'Elegir carpeta…'
$chooseRootButton.Size = [System.Drawing.Size]::new(172, 36)
$chooseRootButton.Location = [System.Drawing.Point]::new(14, 425)
$chooseRootButton.FlatStyle = 'Flat'
$chooseRootButton.FlatAppearance.BorderColor = $script:Colors.Line
$chooseRootButton.BackColor = $script:Colors.White
$chooseRootButton.AccessibleName = 'Elegir la carpeta de infraestructura'
$sidebar.Controls.Add($chooseRootButton)
$chooseRootButton.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Selecciona la carpeta infra del Workshop.'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
        if ((Test-Path -LiteralPath (Join-Path $dialog.SelectedPath 'tasks') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $dialog.SelectedPath 'agents') -PathType Container)) {
            $script:InfraRoot = [System.IO.Path]::GetFullPath($dialog.SelectedPath)
            $script:RootPathLabel.Text = $script:InfraRoot
            Refresh-List
        } else {
            [System.Windows.Forms.MessageBox]::Show('La carpeta seleccionada no parece contener tasks y agents.', 'Carpeta no válida', 'OK', 'Warning') | Out-Null
        }
    }
})

$mainPanel = [System.Windows.Forms.Panel]::new()
$mainPanel.Dock = 'Fill'
$mainPanel.Padding = [System.Windows.Forms.Padding]::new(24, 20, 24, 18)
$mainPanel.BackColor = $script:Colors.Canvas
$rootLayout.Controls.Add($mainPanel, 1, 0)

$script:CategoryTitle = [System.Windows.Forms.Label]::new()
$script:CategoryTitle.Text = 'Tareas'
$script:CategoryTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 22)
$script:CategoryTitle.ForeColor = $script:Colors.Ink
$script:CategoryTitle.AutoSize = $true
$script:CategoryTitle.Location = [System.Drawing.Point]::new(24, 15)
$mainPanel.Controls.Add($script:CategoryTitle)
$intro = [System.Windows.Forms.Label]::new()
$intro.Text = 'Busca recursos y abre sus documentos originales.'
$intro.ForeColor = $script:Colors.Muted
$intro.AutoSize = $true
$intro.Location = [System.Drawing.Point]::new(26, 55)
$mainPanel.Controls.Add($intro)

$script:SearchBox = [System.Windows.Forms.TextBox]::new()
$script:SearchBox.Location = [System.Drawing.Point]::new(24, 91)
$script:SearchBox.Size = [System.Drawing.Size]::new(260, 34)
$script:SearchBox.AccessibleName = 'Buscar recursos por nombre o descripción'
$mainPanel.Controls.Add($script:SearchBox)
$searchHint = [System.Windows.Forms.Label]::new()
$searchHint.Text = 'Buscar por nombre o descripción'
$searchHint.ForeColor = $script:Colors.Muted
$searchHint.AutoSize = $true
$searchHint.Location = [System.Drawing.Point]::new(31, 68)
$mainPanel.Controls.Add($searchHint)
$script:StatusFilter = [System.Windows.Forms.ComboBox]::new()
$script:StatusFilter.DropDownStyle = 'DropDownList'
$script:StatusFilter.Items.AddRange([object[]]@('Todos los estados', 'active', 'completed', 'superseded'))
$script:StatusFilter.SelectedIndex = 1
$script:StatusFilter.Location = [System.Drawing.Point]::new(296, 91)
$script:StatusFilter.Size = [System.Drawing.Size]::new(150, 34)
$script:StatusFilter.AccessibleName = 'Filtrar tareas por estado'
$mainPanel.Controls.Add($script:StatusFilter)
$refreshButton = [System.Windows.Forms.Button]::new()
$refreshButton.Text = 'Actualizar'
$refreshButton.Location = [System.Drawing.Point]::new(458, 90)
$refreshButton.Size = [System.Drawing.Size]::new(100, 36)
$refreshButton.FlatStyle = 'Flat'
$refreshButton.FlatAppearance.BorderColor = $script:Colors.Line
$refreshButton.BackColor = $script:Colors.White
$refreshButton.AccessibleName = 'Actualizar la lista de recursos'
$mainPanel.Controls.Add($refreshButton)

$script:ResourceList = [System.Windows.Forms.ListView]::new()
$script:ResourceList.View = 'Details'
$script:ResourceList.FullRowSelect = $true
$script:ResourceList.MultiSelect = $false
$script:ResourceList.HideSelection = $false
$script:ResourceList.GridLines = $false
$script:ResourceList.Columns.Add('Nombre', 360) | Out-Null
$script:ResourceList.Columns.Add('Estado', 150) | Out-Null
$script:ResourceList.AccessibleName = 'Lista de recursos'
$script:ResourceList.Anchor = 'Top, Bottom, Left, Right'
$script:ResourceList.Location = [System.Drawing.Point]::new(24, 144)
$script:ResourceList.Size = [System.Drawing.Size]::new(590, 300)
$script:ResourceList.BackColor = $script:Colors.White
$mainPanel.Controls.Add($script:ResourceList)

$detailsPanel = [System.Windows.Forms.Panel]::new()
$detailsPanel.Anchor = 'Top, Bottom, Left, Right'
$detailsPanel.Location = [System.Drawing.Point]::new(24, 458)
$detailsPanel.Size = [System.Drawing.Size]::new(590, 155)
$detailsPanel.BackColor = $script:Colors.White
$detailsPanel.Padding = [System.Windows.Forms.Padding]::new(16)
$detailsPanel.BorderStyle = 'FixedSingle'
$mainPanel.Controls.Add($detailsPanel)
$script:DetailTitle = [System.Windows.Forms.Label]::new()
$script:DetailTitle.Text = 'Elige un recurso'
$script:DetailTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 13)
$script:DetailTitle.ForeColor = $script:Colors.Ink
$script:DetailTitle.AutoEllipsis = $true
$script:DetailTitle.Location = [System.Drawing.Point]::new(16, 14)
$script:DetailTitle.Size = [System.Drawing.Size]::new(540, 25)
$detailsPanel.Controls.Add($script:DetailTitle)
$script:DetailDescription = [System.Windows.Forms.TextBox]::new()
$script:DetailDescription.Multiline = $true
$script:DetailDescription.ReadOnly = $true
$script:DetailDescription.BorderStyle = 'None'
$script:DetailDescription.BackColor = $script:Colors.White
$script:DetailDescription.ForeColor = $script:Colors.Muted
$script:DetailDescription.Location = [System.Drawing.Point]::new(17, 45)
$script:DetailDescription.Size = [System.Drawing.Size]::new(540, 54)
$script:DetailDescription.TabStop = $true
$script:DetailDescription.AccessibleName = 'Resumen del recurso seleccionado'
$detailsPanel.Controls.Add($script:DetailDescription)
$script:DetailPath = [System.Windows.Forms.Label]::new()
$script:DetailPath.AutoEllipsis = $true
$script:DetailPath.ForeColor = $script:Colors.Muted
$script:DetailPath.Font = [System.Drawing.Font]::new('Segoe UI', 8.5)
$script:DetailPath.Location = [System.Drawing.Point]::new(17, 106)
$script:DetailPath.Size = [System.Drawing.Size]::new(365, 22)
$detailsPanel.Controls.Add($script:DetailPath)
$script:OpenButton = [System.Windows.Forms.Button]::new()
$script:OpenButton.Text = 'Abrir documento'
$script:OpenButton.Size = [System.Drawing.Size]::new(150, 34)
$script:OpenButton.Anchor = 'Bottom, Right'
$script:OpenButton.Location = [System.Drawing.Point]::new(420, 104)
$script:OpenButton.Enabled = $false
$script:OpenButton.BackColor = $script:Colors.Accent
$script:OpenButton.ForeColor = $script:Colors.ActionText
$script:OpenButton.FlatStyle = 'Flat'
$script:OpenButton.FlatAppearance.BorderSize = 0
$script:OpenButton.AccessibleName = 'Abrir el documento seleccionado'
$detailsPanel.Controls.Add($script:OpenButton)

$script:StatusLabel = [System.Windows.Forms.Label]::new()
$script:StatusLabel.Text = 'Preparado'
$script:StatusLabel.Dock = 'Fill'
$script:StatusLabel.AccessibleName = 'Estado de la aplicación'
$script:StatusLabel.AccessibleRole = 'StatusBar'
$script:StatusLabel.TextAlign = 'MiddleLeft'
$script:StatusLabel.Padding = [System.Windows.Forms.Padding]::new(14, 0, 0, 0)
$script:StatusLabel.BackColor = $script:Colors.White
$script:StatusLabel.ForeColor = $script:Colors.Muted
$statusBar = [System.Windows.Forms.Panel]::new()
$statusBar.Dock = 'Fill'
$statusBar.BackColor = $script:Colors.White
$statusBar.Controls.Add($script:StatusLabel)
$rootLayout.Controls.Add($statusBar, 0, 1)
[System.Windows.Forms.TableLayoutPanel]::SetColumnSpan($statusBar, 2)

$script:SearchBox.Add_TextChanged({ Refresh-List })
$script:StatusFilter.Add_SelectedIndexChanged({ Refresh-List })
$refreshButton.Add_Click({ Refresh-List })
$script:ResourceList.Add_SelectedIndexChanged({
    if ($script:ResourceList.SelectedItems.Count -gt 0) {
        Show-Details $script:ResourceList.SelectedItems[0].Tag
    } else { Show-Details $null }
})
$script:OpenButton.Add_Click({ Open-SelectedFile })
$script:Form.Add_Shown({
    Set-Category 'Tareas'
    $script:ResourceList.Focus()
})
$script:Form.Add_Resize({
    $contentWidth = [Math]::Max(450, $mainPanel.ClientSize.Width - 48)
    $script:ResourceList.Width = $contentWidth
    $script:ResourceList.Height = [Math]::Max(150, $mainPanel.ClientSize.Height - 333)
    $detailsPanel.Location = [System.Drawing.Point]::new(24, $script:ResourceList.Bottom + 14)
    $detailsPanel.Width = $contentWidth
    $detailsPanel.Height = [Math]::Max(145, $mainPanel.ClientSize.Height - $detailsPanel.Top - 8)
    $script:DetailTitle.Width = $contentWidth - 50
    $script:DetailDescription.Width = $contentWidth - 50
    $script:DetailPath.Width = [Math]::Max(170, $contentWidth - 230)
    $script:OpenButton.Left = $contentWidth - 172
})

[System.Windows.Forms.Application]::Run($script:Form)
