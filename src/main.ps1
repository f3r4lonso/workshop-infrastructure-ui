param([string]$InfraRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot 'loader.ps1')

if (-not $InfraRoot) { $InfraRoot = Join-Path $PSScriptRoot '..\..\..\infra' }
$script:InfraRoot = [System.IO.Path]::GetFullPath($InfraRoot)
$script:SmokeTest = ($env:WORKSHOP_UI_SMOKE_TEST -eq '1')
$script:SmokeErrors = [System.Collections.Generic.List[string]]::new()
$script:Section = 'Inicio'
$script:Data = $null
$script:SelectedResource = $null

# Custom drawing (painted sidebar, cards, tiles and list rows) is used only outside high-contrast mode.
# In high contrast every control falls back to system colours and default Windows drawing.
$script:CustomDraw = -not [System.Windows.Forms.SystemInformation]::HighContrast

function New-Color([int]$R, [int]$G, [int]$B) { return [System.Drawing.Color]::FromArgb($R, $G, $B) }

# Palette with WCAG contrast ratios; every text pair is >= 4.5:1 against the background it is drawn on.
$script:Colors = @{
    Ink = New-Color 23 35 56                  # 15.7:1 on white
    Muted = New-Color 85 98 117               # 6.2:1 on white, 5.7:1 on canvas
    Accent = New-Color 31 95 191              # white text on it 6.1:1
    AccentHover = New-Color 24 78 160
    SelectedText = New-Color 31 95 191
    ActionText = [System.Drawing.Color]::White
    Canvas = New-Color 243 245 249
    Line = New-Color 221 227 236
    LineStrong = New-Color 196 205 218
    RowLine = New-Color 236 239 244
    White = [System.Drawing.Color]::White
    SoftBlue = New-Color 232 240 252          # selected row while the list has focus
    RowSelectedIdle = New-Color 238 241 246   # selected row while the list has no focus
    RowHover = New-Color 246 248 252
    ButtonHover = New-Color 236 241 248
    Disabled = New-Color 230 234 240
    Error = New-Color 170 49 44               # 6.6:1 on white
    Sidebar = New-Color 15 30 51              # navy
    SidebarHover = New-Color 27 46 74
    SidebarSelected = New-Color 34 56 90
    SidebarText = New-Color 201 211 225       # 11.1:1 on navy, 7.8:1 on selected
    SidebarMuted = New-Color 143 160 184      # 6.3:1 on navy
    SidebarAccent = New-Color 76 154 255      # selection bar and focus ring, 5.9:1 on navy
    SidebarBorder = New-Color 52 72 104
    NavSelectedText = [System.Drawing.Color]::White
}
if (-not $script:CustomDraw) {
    $script:Colors.Ink = [System.Drawing.SystemColors]::WindowText
    $script:Colors.Muted = [System.Drawing.SystemColors]::WindowText
    $script:Colors.Accent = [System.Drawing.SystemColors]::Highlight
    $script:Colors.AccentHover = [System.Drawing.SystemColors]::Highlight
    $script:Colors.SelectedText = [System.Drawing.SystemColors]::HighlightText
    $script:Colors.ActionText = [System.Drawing.SystemColors]::HighlightText
    $script:Colors.Canvas = [System.Drawing.SystemColors]::Window
    $script:Colors.Line = [System.Drawing.SystemColors]::WindowText
    $script:Colors.LineStrong = [System.Drawing.SystemColors]::WindowText
    $script:Colors.RowLine = [System.Drawing.SystemColors]::WindowText
    $script:Colors.White = [System.Drawing.SystemColors]::Window
    $script:Colors.SoftBlue = [System.Drawing.SystemColors]::Highlight
    $script:Colors.RowSelectedIdle = [System.Drawing.SystemColors]::Highlight
    $script:Colors.RowHover = [System.Drawing.SystemColors]::Window
    $script:Colors.ButtonHover = [System.Drawing.SystemColors]::Window
    $script:Colors.Disabled = [System.Drawing.SystemColors]::Window
    $script:Colors.Error = [System.Drawing.SystemColors]::WindowText
    $script:Colors.Sidebar = [System.Drawing.SystemColors]::Window
    $script:Colors.SidebarHover = [System.Drawing.SystemColors]::Window
    $script:Colors.SidebarSelected = [System.Drawing.SystemColors]::Highlight
    $script:Colors.SidebarText = [System.Drawing.SystemColors]::WindowText
    $script:Colors.SidebarMuted = [System.Drawing.SystemColors]::WindowText
    $script:Colors.SidebarAccent = [System.Drawing.SystemColors]::Highlight
    $script:Colors.SidebarBorder = [System.Drawing.SystemColors]::WindowText
    $script:Colors.NavSelectedText = [System.Drawing.SystemColors]::HighlightText
}

# One colour per resource type, reused by the Inicio tiles, list badges and the detail card band.
# Fore is dark text on the light Back tint; every pair is >= 5.2:1.
$script:TypeThemes = @{
    'Tareas' = @{ Fore = (New-Color 154 60 12); Back = (New-Color 252 233 222) }        # 5.9:1
    'Agentes' = @{ Fore = (New-Color 30 79 168); Back = (New-Color 227 236 251) }       # 6.5:1
    'Skills' = @{ Fore = (New-Color 91 50 180); Back = (New-Color 238 232 251) }        # 6.9:1
    'Documentos' = @{ Fore = (New-Color 15 110 110); Back = (New-Color 223 243 241) }   # 5.2:1
    'Aplicaciones' = @{ Fore = (New-Color 31 112 56); Back = (New-Color 226 244 230) }  # 5.3:1
    'Clientes IA' = @{ Fore = (New-Color 68 84 106); Back = (New-Color 230 234 240) }   # 6.4:1
    'Asistentes' = @{ Fore = (New-Color 160 48 106); Back = (New-Color 251 230 240) }   # 5.7:1
    'Aviso' = @{ Fore = (New-Color 163 38 31); Back = (New-Color 251 228 226) }         # 6.1:1
    'Otros' = @{ Fore = (New-Color 68 84 106); Back = (New-Color 230 234 240) }
}
$script:StatusThemes = @{
    'active' = $script:TypeThemes['Aplicaciones']    # green
    'waiting' = @{ Fore = (New-Color 138 75 0); Back = (New-Color 253 240 220) }   # amber, 6.1:1
    'other' = $script:TypeThemes['Otros']            # slate: completed, retired, superseded
}

$script:Fonts = @{
    RowTitle = [System.Drawing.Font]::new('Segoe UI Semibold', 10)
    RowDesc = [System.Drawing.Font]::new('Segoe UI', 9)
    Badge = [System.Drawing.Font]::new('Segoe UI Semibold', 8.25)
    Caption = [System.Drawing.Font]::new('Segoe UI', 8.25)
    GroupLabel = [System.Drawing.Font]::new('Segoe UI Semibold', 9)
    HeaderRow = [System.Drawing.Font]::new('Segoe UI Semibold', 9.5)
    Header = [System.Drawing.Font]::new('Segoe UI Semibold', 8.25)
    NavCount = [System.Drawing.Font]::new('Segoe UI', 9)
    TileNumber = [System.Drawing.Font]::new('Segoe UI Semibold', 20)
    TileSuffix = [System.Drawing.Font]::new('Segoe UI', 9.5)
    TileLabel = [System.Drawing.Font]::new('Segoe UI', 9.5)
}
$script:TextFlags = @{
    Left = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, NoPrefix, SingleLine'
    TopLeft = [System.Windows.Forms.TextFormatFlags]'Left, Top, EndEllipsis, NoPrefix, SingleLine'
    Right = [System.Windows.Forms.TextFormatFlags]'Right, VerticalCenter, NoPrefix, SingleLine'
    Center = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, EndEllipsis, NoPrefix, SingleLine'
    Measure = [System.Windows.Forms.TextFormatFlags]'NoPadding, NoPrefix, SingleLine'
}

# Brushes and pens are created once per colour and reused by every paint handler.
$script:BrushCache = @{}
$script:PenCache = @{}
$script:ButtonRest = @{}
$script:NavCounts = @{}
$script:TileInfo = @{}
$script:HoverIndex = -1
$script:ShowTypeColumn = $true
$script:ShowDetailColumn = $true
$script:ListShowContext = $false
$script:ListGroupedByDetail = $false
$script:ListDividers = $false
$script:WideLayout = $null
$script:InLayout = $false
$script:DetailCard = $null
$script:Body = $null
$script:SearchCard = $null
$script:ListCard = $null
$script:UsageCode = $null

$script:TaskFilters = @('Activas', 'Todas', 'Completadas', 'Retiradas o sustituidas')
$script:SectionIntros = @{
    'Inicio' = 'Todo lo que hay en el Workshop. Elige una sección o escribe en el buscador.'
    'Tareas' = 'Encargos completos que se entregan a un cliente de IA. Ejecuta solo las activas.'
    'Agentes' = 'Roles especializados (revisor, diseñador, auditor…) que un cliente de IA puede usar.'
    'Skills' = 'Métodos y listas de comprobación que un cliente de IA sigue durante la sesión.'
    'Documentos' = 'Guías, políticas, investigaciones y planes del Workshop y de cada aplicación.'
    'Aplicaciones' = 'Las aplicaciones del Workshop. Esta ventana no las inicia: muestra cómo hacerlo.'
    'Clientes IA' = 'Cómo encuentra y usa cada cliente de IA los recursos compartidos.'
    'Asistentes' = 'Tus asistentes personales: planificador, ingeniero de prompts y redactor.'
}

function Test-TaskFilter($Resource, [string]$Filter) {
    switch ($Filter) {
        'Activas' { return (Test-ActiveTask $Resource) }
        'Completadas' { return ((Get-TaskState $Resource.Status) -eq 'completed') }
        'Retiradas o sustituidas' { return ((Get-TaskState $Resource.Status) -in @('retired', 'superseded')) }
    }
    return $true
}

function Set-Status([string]$Message, [bool]$IsError = $false) {
    $script:StatusLabel.Text = $Message
    $script:StatusLabel.AccessibleName = $Message
    $script:StatusLabel.ForeColor = if ($IsError) { $script:Colors.Error } else { $script:Colors.Muted }
    # UI Automation notifications exist from .NET Framework 4.7.2; older runtimes skip this silently.
    $accessible = $script:StatusLabel.AccessibilityObject
    if ($accessible.PSObject.Methods.Name -contains 'RaiseAutomationNotification') {
        try {
            [void]$accessible.RaiseAutomationNotification(
                [System.Windows.Forms.Automation.AutomationNotificationKind]::Other,
                [System.Windows.Forms.Automation.AutomationNotificationProcessing]::MostRecent, $Message)
        } catch { }
    }
}

# Runs an event handler and turns any failure into a Spanish status message instead of a crash dialog.
function Invoke-Safely([scriptblock]$Action) {
    try {
        & $Action
    } catch {
        $script:SmokeErrors.Add($_.Exception.Message + ' @ ' + $_.ScriptStackTrace)
        Set-Status 'Algo falló al hacer esta acción. Pulsa Actualizar (F5) y vuelve a intentarlo.' $true
    }
}

function New-Label([string]$Text, [float]$Size = 10, [bool]$Bold = $false) {
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $fontName = if ($Bold) { 'Segoe UI Semibold' } else { 'Segoe UI' }
    $label.Font = [System.Drawing.Font]::new($fontName, $Size)
    $label.ForeColor = $script:Colors.Ink
    $label.AutoSize = $true
    $label.UseMnemonic = $false
    $label.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 4)
    return $label
}

# Applies colours to a flat button and remembers its resting border so the focus cue can restore it.
function Set-ButtonLook($Button, $Back, $Fore, $Border, [int]$BorderSize, $Hover, $Focus) {
    $Button.BackColor = $Back
    $Button.ForeColor = $Fore
    $Button.FlatAppearance.BorderColor = $Border
    $Button.FlatAppearance.BorderSize = $BorderSize
    if ($script:CustomDraw) {
        $Button.FlatAppearance.MouseOverBackColor = $Hover
        $Button.FlatAppearance.MouseDownBackColor = $Hover
    } else {
        $Focus = [System.Drawing.SystemColors]::Highlight
    }
    $script:ButtonRest[$Button] = @{ Size = $BorderSize; Color = $Border; Focus = $Focus }
}

function New-FlatButton([string]$Text, [string]$AccessibleName, [bool]$Primary = $false) {
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.AutoSize = $true
    $button.MinimumSize = [System.Drawing.Size]::new(100, 36)
    $button.Padding = [System.Windows.Forms.Padding]::new(10, 0, 10, 0)
    $button.FlatStyle = 'Flat'
    $button.Cursor = 'Hand'
    $button.AccessibleName = $AccessibleName
    if ($Primary) {
        $button.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 10)
        Set-ButtonLook $button $script:Colors.Accent $script:Colors.ActionText $script:Colors.Accent 0 $script:Colors.AccentHover $script:Colors.Ink
        if ($script:CustomDraw) {
            # A disabled accent button would show grey text on blue; switch to a neutral fill instead.
            $button.Add_EnabledChanged({
                param($sender, $eventArgs)
                $sender.BackColor = if ($sender.Enabled) { $script:Colors.Accent } else { $script:Colors.Disabled }
            })
        }
    } else {
        Set-ButtonLook $button $script:Colors.White $script:Colors.Ink $script:Colors.LineStrong 1 $script:Colors.ButtonHover $script:Colors.Accent
    }
    Add-FocusCue $button
    return $button
}

# Flat buttons hide the system focus cue; draw a thick border while focused. Painted buttons
# (sections, tiles) draw their own ring in their Paint handler and are repainted here.
function Add-FocusCue($Button) {
    $Button.Add_GotFocus({
        param($sender, $eventArgs)
        $rest = $script:ButtonRest[$sender]
        $sender.FlatAppearance.BorderSize = if ($script:CustomDraw) { 2 } else { 3 }
        $sender.FlatAppearance.BorderColor = if ($rest) { $rest.Focus } else { [System.Drawing.SystemColors]::Highlight }
        $sender.Invalidate()
    })
    $Button.Add_LostFocus({
        param($sender, $eventArgs)
        $rest = $script:ButtonRest[$sender]
        if ($rest) {
            $sender.FlatAppearance.BorderSize = $rest.Size
            $sender.FlatAppearance.BorderColor = $rest.Color
        } else {
            $sender.FlatAppearance.BorderSize = 1
            $sender.FlatAppearance.BorderColor = $script:Colors.Line
        }
        $sender.Invalidate()
    })
}

# DoubleBuffered is protected; set it through reflection (no compiled code) to avoid flicker when painting.
function Enable-DoubleBuffer($Control) {
    try {
        $property = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic')
        $property.SetValue($Control, $true, $null)
    } catch { }
}

# ---------- Drawing helpers (used only when $script:CustomDraw) ----------

function Get-Brush([System.Drawing.Color]$Color) {
    $key = $Color.ToArgb()
    if (-not $script:BrushCache.ContainsKey($key)) { $script:BrushCache[$key] = [System.Drawing.SolidBrush]::new($Color) }
    return $script:BrushCache[$key]
}

function Get-Pen([System.Drawing.Color]$Color, [float]$Width = 1) {
    $key = '{0}/{1}' -f $Color.ToArgb(), $Width
    if (-not $script:PenCache.ContainsKey($key)) { $script:PenCache[$key] = [System.Drawing.Pen]::new($Color, $Width) }
    return $script:PenCache[$key]
}

function New-RoundedPath([System.Drawing.Rectangle]$Rect, [int]$Radius) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = [Math]::Min($Radius * 2, [Math]::Min($Rect.Width, $Rect.Height))
    if ($diameter -le 1) {
        $path.AddRectangle($Rect)
        return $path
    }
    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-Rect([double]$X, [double]$Y, [double]$Width, [double]$Height) {
    return [System.Drawing.Rectangle]::new([int]$X, [int]$Y, [int][Math]::Max(0, $Width), [int][Math]::Max(0, $Height))
}

function Draw-Text($Graphics, [string]$Text, $Font, [System.Drawing.Rectangle]$Rect, [System.Drawing.Color]$Color, $Flags) {
    if (-not $Text -or $Rect.Width -le 0 -or $Rect.Height -le 0) { return }
    [System.Windows.Forms.TextRenderer]::DrawText($Graphics, $Text, $Font, $Rect, $Color, $Flags)
}

function Get-TypeTheme([string]$Section) {
    if ($Section -and $script:TypeThemes.ContainsKey($Section)) { return $script:TypeThemes[$Section] }
    return $script:TypeThemes['Otros']
}

function Get-StatusTheme($Resource) {
    $state = Get-TaskState ([string]$Resource.Status)
    if ($state -eq 'active') { return $script:StatusThemes['active'] }
    if ($state -eq 'waiting') { return $script:StatusThemes['waiting'] }
    return $script:StatusThemes['other']
}

# Pill-shaped badge; returns its width so callers can place text after it.
function Draw-Badge($Graphics, [string]$Text, $Theme, [int]$X, [int]$CenterY, [int]$MaxWidth) {
    if (-not $Text -or $MaxWidth -lt 28) { return 0 }
    $font = $script:Fonts.Badge
    $size = [System.Windows.Forms.TextRenderer]::MeasureText($Graphics, $Text, $font, [System.Drawing.Size]::new(2000, 100), $script:TextFlags.Measure)
    $width = [Math]::Min($size.Width + 20, $MaxWidth)
    $rect = New-Rect $X ($CenterY - 11) $width 22
    $path = New-RoundedPath $rect 11
    try {
        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $Graphics.FillPath((Get-Brush $Theme.Back), $path)
        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::Default
    } finally { $path.Dispose() }
    Draw-Text $Graphics $Text $font $rect $Theme.Fore $script:TextFlags.Center
    return $width
}

function Test-MouseOver($Control) {
    return $Control.ClientRectangle.Contains($Control.PointToClient([System.Windows.Forms.Cursor]::Position))
}

# Border colour and width of a card; the card that holds the focused control gets the accent ring.
function Get-CardBorder($Card) {
    if (($Card -eq $script:SearchCard -and $script:SearchBox.Focused) -or
        ($Card -eq $script:ListCard -and $script:ResourceList.Focused) -or
        ($Card -eq $script:UsageCode -and $script:UsageBox.Focused)) {
        return @($script:Colors.Accent, 2)
    }
    return @($script:Colors.Line, 1)
}

# Rounded card: parent colour in the corners, own fill, 1 px border (2 px accent while focused).
function Draw-Card($Card, $Graphics) {
    $g = $Graphics
    $g.Clear($Card.Parent.BackColor)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $width = $Card.Width
    $height = $Card.Height
    $path = New-RoundedPath (New-Rect 0 0 ($width - 1) ($height - 1)) 8
    try {
        $g.FillPath((Get-Brush $Card.BackColor), $path)
        if ($Card -eq $script:DetailCard -and $script:SelectedResource) {
            # Thin band in the colour of the selected resource's type.
            $g.SetClip($path)
            $g.FillRectangle((Get-Brush (Get-TypeTheme $script:SelectedResource.Section).Fore), 0, 0, $width, 4)
            $g.ResetClip()
        }
        $border = Get-CardBorder $Card
        if ($border[1] -gt 1) {
            $ring = New-RoundedPath (New-Rect 1 1 ($width - 3) ($height - 3)) 8
            try { $g.DrawPath((Get-Pen $border[0] 2), $ring) } finally { $ring.Dispose() }
        } else {
            $g.DrawPath((Get-Pen $border[0] 1), $path)
        }
    } finally { $path.Dispose() }
    if ($Card -eq $script:SearchCard) {
        # Magnifier glyph to the left of the search text.
        $pen = Get-Pen $script:Colors.Muted 2
        $g.DrawEllipse($pen, 14, 12, 11, 11)
        $g.DrawLine($pen, 23, 21, 28, 26)
    }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::Default
}

# Fallback when a custom painter fails: plain fill, the control's own text, a border for cards and a
# standard focus rectangle, so a control is never left blank.
function Draw-PlainControl($Control, $Graphics) {
    try {
        $Graphics.ResetClip()
        $Graphics.Clear($Control.BackColor)
        $rect = $Control.ClientRectangle
        if ($Control -is [System.Windows.Forms.ButtonBase]) {
            $flags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, WordBreak, NoPrefix'
            [System.Windows.Forms.TextRenderer]::DrawText($Graphics, [string]$Control.Text, $Control.Font, $rect, $Control.ForeColor, $flags)
            $Graphics.DrawRectangle([System.Drawing.Pens]::Gray, 0, 0, $rect.Width - 1, $rect.Height - 1)
            if ($Control.Focused) {
                [System.Windows.Forms.ControlPaint]::DrawFocusRectangle($Graphics, [System.Drawing.Rectangle]::Inflate($rect, -3, -3))
            }
        } else {
            $Graphics.DrawRectangle([System.Drawing.Pens]::Gray, 0, 0, $rect.Width - 1, $rect.Height - 1)
        }
    } catch { }
}

function Add-CardPaint($Card) {
    if (-not $script:CustomDraw) { return }
    Enable-DoubleBuffer $Card
    $Card.Add_Paint({
        param($sender, $eventArgs)
        try { Draw-Card $sender $eventArgs.Graphics } catch { Draw-PlainControl $sender $eventArgs.Graphics }
    })
    $Card.Add_Resize({ param($sender, $eventArgs) $sender.Invalidate() })
}

# The section shown as current in the sidebar; none while a search is active (results span all sections).
function Get-CurrentNav {
    if ($script:SearchBox -and $script:SearchBox.Text.Trim()) { return '' }
    return $script:Section
}

function Draw-NavButton($Button, $Graphics) {
    $g = $Graphics
    $width = $Button.Width
    $height = $Button.Height
    $name = [string]$Button.Tag
    $selected = ($name -eq (Get-CurrentNav))
    $g.Clear($script:Colors.Sidebar)
    $back = $null
    if ($selected) { $back = $script:Colors.SidebarSelected }
    elseif (Test-MouseOver $Button) { $back = $script:Colors.SidebarHover }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if ($back) {
        $path = New-RoundedPath (New-Rect 0 0 ($width - 1) ($height - 1)) 6
        try { $g.FillPath((Get-Brush $back), $path) } finally { $path.Dispose() }
    }
    if ($selected) { $g.FillRectangle((Get-Brush $script:Colors.SidebarAccent), 0, 9, 3, $height - 18) }
    if ($Button.Focused) {
        $ring = New-RoundedPath (New-Rect 1 1 ($width - 3) ($height - 3)) 6
        try { $g.DrawPath((Get-Pen $script:Colors.SidebarAccent 2), $ring) } finally { $ring.Dispose() }
    }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::Default
    $font = if ($selected) { $script:NavFontSelected } else { $script:NavFont }
    $fore = if ($selected) { $script:Colors.NavSelectedText } else { $script:Colors.SidebarText }
    Draw-Text $g $name $font (New-Rect 16 0 ($width - 64) $height) $fore $script:TextFlags.Left
    if ($name -ne 'Inicio' -and $script:NavCounts.ContainsKey($name)) {
        # Muted count on navy is 6.3:1; on the selected fill use the lighter text colour (7.8:1).
        $countColor = if ($selected) { $script:Colors.SidebarText } else { $script:Colors.SidebarMuted }
        Draw-Text $g ([string]$script:NavCounts[$name]) $script:Fonts.NavCount (New-Rect ($width - 52) 0 40 $height) $countColor $script:TextFlags.Right
    }
}

function Draw-Tile($Tile, $Graphics) {
    $g = $Graphics
    $width = $Tile.Width
    $height = $Tile.Height
    $name = [string]$Tile.Tag
    $hover = Test-MouseOver $Tile
    $g.Clear($Tile.Parent.BackColor)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path = New-RoundedPath (New-Rect 0 0 ($width - 1) ($height - 1)) 8
    try {
        $fill = if ($hover) { $script:Colors.RowHover } else { $script:Colors.White }
        $g.FillPath((Get-Brush $fill), $path)
        $g.SetClip($path)
        $g.FillRectangle((Get-Brush (Get-TypeTheme $name).Fore), 0, 0, 4, $height)
        $g.ResetClip()
        if ($Tile.Focused) {
            $ring = New-RoundedPath (New-Rect 1 1 ($width - 3) ($height - 3)) 8
            try { $g.DrawPath((Get-Pen $script:Colors.Accent 2), $ring) } finally { $ring.Dispose() }
        } else {
            $borderColor = if ($hover) { $script:Colors.LineStrong } else { $script:Colors.Line }
            $g.DrawPath((Get-Pen $borderColor 1), $path)
        }
    } finally { $path.Dispose() }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::Default
    $info = $script:TileInfo[$name]
    if (-not $info) { $info = @{ Number = '0'; Suffix = ''; Label = $name } }
    $numberRect = New-Rect 16 6 ($width - 22) 40
    Draw-Text $g $info.Number $script:Fonts.TileNumber $numberRect $script:Colors.Ink $script:TextFlags.Left
    if ($info.Suffix) {
        $numberWidth = [System.Windows.Forms.TextRenderer]::MeasureText($g, $info.Number, $script:Fonts.TileNumber, [System.Drawing.Size]::new(500, 60), $script:TextFlags.Measure).Width
        $x = 16 + $numberWidth + 6
        Draw-Text $g $info.Suffix $script:Fonts.TileSuffix (New-Rect $x 14 ($width - $x - 6) 30) $script:Colors.Muted $script:TextFlags.Left
    }
    Draw-Text $g $info.Label $script:Fonts.TileLabel (New-Rect 16 46 ($width - 22) 20) $script:Colors.Muted $script:TextFlags.Left
}

# ---------- Resource list drawing ----------

# Group header rows are ListViewItems whose Tag is a marker with Section = 'Grupo'.
function Test-HeaderItem($Item) {
    return ($null -ne $Item -and $null -ne $Item.Tag -and [string]$Item.Tag.Section -eq 'Grupo')
}

function Get-ResourceItems {
    return @($script:ResourceList.Items | Where-Object { -not (Test-HeaderItem $_) })
}

# Selects the n-th real resource (header rows skipped); returns $false when there is none.
function Select-ResourceAt([int]$Position) {
    $items = @(Get-ResourceItems)
    if ($Position -lt 0 -or $Position -ge $items.Count) { return $false }
    $items[$Position].Selected = $true
    $items[$Position].Focused = $true
    $items[$Position].EnsureVisible()
    return $true
}

function Select-FirstResource { return (Select-ResourceAt 0) }

# Short task state for the list pill; the full status (with dates) stays in the detail meta line.
function Get-ShortStatus([string]$Status) {
    switch (Get-TaskState $Status) {
        'active' { return 'Activa' }
        'waiting' { return 'En espera' }
        'completed' { return 'Completada' }
        'retired' { return 'Retirada' }
        'superseded' { return 'Sustituida' }
    }
    return (Get-StatusLabel $Status)
}

function Get-RowBack($Item, [int]$Index) {
    if (Test-HeaderItem $Item) { return $script:Colors.White }
    if ($Item.Selected) {
        if ($script:ResourceList.Focused) { return $script:Colors.SoftBlue }
        return $script:Colors.RowSelectedIdle
    }
    if ($Index -eq $script:HoverIndex) { return $script:Colors.RowHover }
    return $script:Colors.White
}

function Draw-ListHeader($DrawArgs) {
    $g = $DrawArgs.Graphics
    $bounds = $DrawArgs.Bounds
    if ($bounds.Width -le 0) { return }
    $g.FillRectangle((Get-Brush $script:Colors.White), $bounds)
    $g.FillRectangle((Get-Brush $script:Colors.Line), $bounds.X, $bounds.Bottom - 1, $bounds.Width, 1)
    $left = if ($DrawArgs.ColumnIndex -eq 0) { 16 } else { 10 }
    $text = ([string]$DrawArgs.Header.Text).ToUpperInvariant()
    Draw-Text $g $text $script:Fonts.Header (New-Rect ($bounds.X + $left) $bounds.Y ($bounds.Width - $left - 4) $bounds.Height) $script:Colors.Muted $script:TextFlags.Left
}

function Draw-ListCell($DrawArgs) {
    $list = $script:ResourceList
    $item = $DrawArgs.Item
    $index = $DrawArgs.ItemIndex
    $column = $DrawArgs.ColumnIndex
    $columnWidth = $list.Columns[$column].Width
    if ($columnWidth -le 0) { return }
    $g = $DrawArgs.Graphics
    # For column 0 the event bounds can span the whole row, so use the column width.
    $cell = New-Rect $DrawArgs.Bounds.X $DrawArgs.Bounds.Y $columnWidth $DrawArgs.Bounds.Height
    $g.FillRectangle((Get-Brush (Get-RowBack $item $index)), $cell)

    if (Test-HeaderItem $item) {
        # Group header: white gap on top, then a full-width tinted band with bold text and a type dot.
        $band = New-Rect $cell.X ($cell.Y + 14) $cell.Width ($cell.Height - 14)
        $bandColor = if ($item.Selected) { $script:Colors.SoftBlue } else { $script:Colors.Canvas }
        $g.FillRectangle((Get-Brush $bandColor), $band)
        $g.FillRectangle((Get-Brush $script:Colors.Line), $band.X, $band.Bottom - 1, $band.Width, 1)
        if ($column -eq 0) {
            $left = $cell.X + 16
            $themeSection = [string]$item.Tag.GroupSection
            if ($themeSection) {
                $dotY = $band.Y + [int](($band.Height - 8) / 2)
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.FillEllipse((Get-Brush (Get-TypeTheme $themeSection).Fore), $left, $dotY, 8, 8)
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::Default
                $left += 16
            }
            Draw-Text $g ([string]$item.Text) $script:Fonts.HeaderRow (New-Rect $left $band.Y ($cell.Right - $left - 8) ($band.Height - 1)) $script:Colors.Ink $script:TextFlags.Left
        }
        return
    }

    $g.FillRectangle((Get-Brush $script:Colors.RowLine), $cell.X, $cell.Bottom - 1, $cell.Width, 1)

    $resource = $item.Tag
    $centerY = $cell.Y + [int](($cell.Height - 1) / 2)
    if ($column -eq 0) {
        if ($item.Selected) {
            # Unfocused selection keeps a visible bar in Muted (6.2:1 on the row).
            $barColor = if ($list.Focused) { $script:Colors.Accent } else { $script:Colors.Muted }
            $g.FillRectangle((Get-Brush $barColor), $cell.X, $cell.Y, 3, $cell.Height - 1)
        }
        $description = ''
        if ($resource) { $description = (([string]$resource.Description) -replace '\s+', ' ').Trim() }
        $left = $cell.X + 16
        $textWidth = $cell.Width - 24
        if ($description) {
            Draw-Text $g ([string]$item.Text) $script:Fonts.RowTitle (New-Rect $left ($cell.Y + 6) $textWidth 20) $script:Colors.Ink $script:TextFlags.TopLeft
            Draw-Text $g $description $script:Fonts.RowDesc (New-Rect $left ($cell.Y + 26) $textWidth 18) $script:Colors.Muted $script:TextFlags.TopLeft
        } else {
            Draw-Text $g ([string]$item.Text) $script:Fonts.RowTitle (New-Rect $left $cell.Y $textWidth ($cell.Height - 1)) $script:Colors.Ink $script:TextFlags.Left
        }
        return
    }
    if ($column -eq 1) {
        $section = if ($resource) { [string]$resource.Section } else { '' }
        [void](Draw-Badge $g ([string]$item.SubItems[1].Text) (Get-TypeTheme $section) ($cell.X + 10) $centerY ($cell.Width - 16))
        return
    }

    # Column 2 (Detalle) shows only a task status pill or a modification date; area text is not drawn.
    $text = [string]$item.SubItems[2].Text
    $kind = [string]$item.SubItems[2].Tag
    $left = $cell.X + 10
    $textWidth = $cell.Width - 16
    if ($kind -eq 'status' -and $text -and $resource) {
        [void](Draw-Badge $g $text (Get-StatusTheme $resource) $left $centerY $textWidth)
    } elseif ($kind -eq 'date') {
        Draw-Text $g $text $script:Fonts.RowDesc (New-Rect $left ($centerY - 9) $textWidth 18) $script:Colors.Muted $script:TextFlags.Left
    }
}

function Update-ListColumns {
    $list = $script:ResourceList
    $width = $list.ClientSize.Width - 2
    if ($width -le 0) { return }
    $typeWidth = if ($script:ShowTypeColumn) { 110 } else { 0 }
    $detailWidth = if ($script:ShowDetailColumn) { 128 } else { 0 }
    $nameWidth = [Math]::Max(160, $width - $typeWidth - $detailWidth)
    if ($list.Columns[1].Width -ne $typeWidth) { $list.Columns[1].Width = $typeWidth }
    if ($list.Columns[2].Width -ne $detailWidth) { $list.Columns[2].Width = $detailWidth }
    if ($list.Columns[0].Width -ne $nameWidth) { $list.Columns[0].Width = $nameWidth }
}

function Set-HoverIndex([int]$Index) {
    $list = $script:ResourceList
    if ($Index -ge 0 -and $Index -lt $list.Items.Count -and (Test-HeaderItem $list.Items[$Index])) { $Index = -1 }
    if ($Index -eq $script:HoverIndex) { return }
    foreach ($old in @($script:HoverIndex, $Index)) {
        if ($old -ge 0 -and $old -lt $list.Items.Count) { $list.Invalidate($list.Items[$old].Bounds) }
    }
    $script:HoverIndex = $Index
}

function Get-SectionCount([string]$Section) {
    if (-not $script:Data) { return 0 }
    return @($script:Data.Items | Where-Object { $_.Section -eq $Section }).Count
}

function Get-ActiveTaskCount {
    if (-not $script:Data) { return 0 }
    return @($script:Data.Items | Where-Object { Test-ActiveTask $_ }).Count
}

function Update-Counts {
    foreach ($button in $script:NavButtons) {
        $name = [string]$button.Tag
        if ($name -eq 'Inicio') { continue }
        $count = Get-SectionCount $name
        $button.Text = "$name ($count)"
        $script:NavCounts[$name] = $count
    }
    Update-NavState
    foreach ($tile in $script:Tiles) {
        $name = [string]$tile.Tag
        $count = Get-SectionCount $name
        if ($name -eq 'Tareas') {
            $active = Get-ActiveTaskCount
            $tile.Text = "$active activas`r`nde $count tareas"
            $tile.AccessibleName = "$active activas de $count tareas. Abrir la sección Tareas"
            $script:TileInfo[$name] = @{ Number = [string]$active; Suffix = "de $count"; Label = 'Tareas activas' }
        } else {
            $tile.Text = "$count`r`n$name"
            $tile.AccessibleName = "$count $name. Abrir la sección"
            $script:TileInfo[$name] = @{ Number = [string]$count; Suffix = ''; Label = $name }
        }
        $tile.Invalidate()
    }
    $script:RootPathLabel.Text = $script:InfraRoot
}

function Load-Data {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not (Test-Path -LiteralPath $script:InfraRoot -PathType Container)) {
        $script:Data = $null
        Update-Counts
        return $timer.ElapsedMilliseconds
    }
    $script:Data = Get-WorkshopData $script:InfraRoot
    Update-Counts
    return $timer.ElapsedMilliseconds
}

function Get-Group([hashtable]$Groups, [string]$Header) {
    if (-not $Header) { $Header = 'Otros' }
    if (-not $Groups.ContainsKey($Header)) {
        $group = [System.Windows.Forms.ListViewGroup]::new($Header, [System.Windows.Forms.HorizontalAlignment]::Left)
        [void]$script:ResourceList.Groups.Add($group)
        $Groups[$Header] = $group
    }
    return $Groups[$Header]
}

# Third column: task status (short), a date, or the area. Its subitem Tag says which ('status', 'date', '').
function Add-ListItem($Resource, [string]$GroupHeader, [hashtable]$Groups, [object]$Third = $null, [string]$ThirdKind = '') {
    $item = [System.Windows.Forms.ListViewItem]::new([string]$Resource.Title)
    [void]$item.SubItems.Add([string]$Resource.TypeLabel)
    if ($null -eq $Third) {
        if ($Resource.Section -eq 'Tareas') {
            $Third = Get-ShortStatus $Resource.Status
            $ThirdKind = 'status'
        } else {
            $Third = [string]$Resource.Area
        }
    }
    $thirdItem = $item.SubItems.Add([string]$Third)
    if ($ThirdKind) { $thirdItem.Tag = $ThirdKind }
    $item.Tag = $Resource
    $item.Name = [string]$GroupHeader
    $item.ToolTipText = [string]$Resource.Description
    if ($Groups -and -not $script:CustomDraw) { $item.Group = Get-Group $Groups $GroupHeader }
    [void]$script:ResourceList.Items.Add($item)
}

# Owner-drawn group header row (high contrast keeps native ListView groups instead).
function Add-HeaderItem([string]$Text, [string]$ThemeSection) {
    $marker = [pscustomobject]@{
        Section = 'Grupo'; GroupSection = $ThemeSection; TypeLabel = ''; Name = ''; Title = $Text
        Description = ''; Status = ''; Area = ''; Path = ''; RelativePath = ''; Usage = ''; UsageHint = ''
        Modified = [datetime]::MinValue
    }
    $item = [System.Windows.Forms.ListViewItem]::new($Text)
    [void]$item.SubItems.Add('')
    [void]$item.SubItems.Add('')
    $item.Tag = $marker
    $item.Name = $Text
    [void]$script:ResourceList.Items.Add($item)
}

# Adds one group: a header row "Name (count)" when owner drawing, then its resources.
function Add-ListBlock([string]$Header, [object[]]$Resources, [hashtable]$Groups, [string]$Kind = '', [string]$ThemeSection = '') {
    if (-not $Resources -or $Resources.Count -eq 0) { return }
    if ($script:CustomDraw -and $Header) { Add-HeaderItem ('{0} ({1})' -f $Header, $Resources.Count) $ThemeSection }
    foreach ($resource in $Resources) {
        if ($Kind -eq 'date') { Add-ListItem $resource $Header $Groups $resource.Modified.ToString('dd/MM/yyyy HH:mm') 'date' }
        elseif ($Kind -eq 'warning') { Add-ListItem $resource $Header $Groups '' }
        else { Add-ListItem $resource $Header $Groups }
    }
}

function New-WarningResource([string]$Message) {
    return [pscustomobject]@{
        Section = 'Aviso'; TypeLabel = 'Aviso'; Name = ''; Title = $Message
        Description = ($Message + "`r`n`r`nEs solo informativo: la app sigue funcionando. Para corregirlo, actualiza el catálogo o WORKSHOP-CONTEXT.md (o pídeselo a tu cliente de IA) y pulsa Actualizar.")
        Status = ''; Area = ''; Path = ''; RelativePath = ''; Usage = ''; UsageHint = 'Los avisos no tienen nada que copiar.'
        Modified = [datetime]::MinValue
    }
}

function Render-List {
    $query = $script:SearchBox.Text.Trim()
    # Search results span every section, so no section is shown as current while a query is active.
    Update-NavState
    $script:ResourceList.BeginUpdate()
    $script:ResourceList.Items.Clear()
    $script:ResourceList.Groups.Clear()
    $script:HoverIndex = -1
    $groups = @{}
    $shown = 0

    if (-not $script:Data) {
        $script:ResourceList.EndUpdate()
        Show-Details $null
        Set-Status 'No se encontró la carpeta infra. Pulsa «Elegir carpeta…» para indicar dónde está.' $true
        return
    }

    # Native groups only in high contrast; owner drawing inserts header rows instead.
    $script:ResourceList.ShowGroups = (-not $script:CustomDraw)
    $isHome = ($script:Section -eq 'Inicio' -and -not $query)
    $groupedSection = (-not $query -and $script:Section -in @('Agentes', 'Skills', 'Documentos'))
    $script:ShowTypeColumn = ($isHome -or [bool]$query)
    $script:ShowDetailColumn = ($isHome -or [bool]$query -or $script:Section -eq 'Tareas')
    $script:ResourceList.Columns[2].Text = if (-not $query -and $script:Section -eq 'Tareas') { 'Estado' } else { 'Detalle' }
    $showFilter = ($script:Section -eq 'Tareas' -and -not $query)
    $script:StatusFilter.Visible = $showFilter
    $script:FilterLabel.Visible = $showFilter
    $script:TilePanel.Visible = ($script:Section -eq 'Inicio' -and -not $query)
    if ($query) {
        $script:CategoryTitle.Text = 'Resultados de búsqueda'
        $script:IntroLabel.Text = "Buscando «$query» en todas las secciones. Pulsa Esc para limpiar la búsqueda."
        $found = @($script:Data.Items | Where-Object { Test-ResourceMatch $_ $query })
        foreach ($section in $script:Sections) {
            $sectionItems = @($found | Where-Object { $_.Section -eq $section } | Sort-Object Title)
            Add-ListBlock $section $sectionItems $groups '' $section
            $shown += $sectionItems.Count
        }
    } elseif ($script:Section -eq 'Inicio') {
        $activeTasks = @($script:Data.Items | Where-Object { Test-ActiveTask $_ } | Sort-Object Title)
        Add-ListBlock 'Tareas activas' $activeTasks $groups '' 'Tareas'
        $shown += $activeTasks.Count
        $recent = @($script:Data.Items | Sort-Object Modified -Descending | Select-Object -First 5)
        Add-ListBlock 'Modificado recientemente' $recent $groups 'date'
        $shown += $recent.Count
        $warnings = @($script:Data.Warnings | ForEach-Object { New-WarningResource $_ })
        Add-ListBlock 'Avisos' $warnings $groups 'warning' 'Aviso'
    } else {
        $filter = [string]$script:StatusFilter.SelectedItem
        $items = @($script:Data.Items | Where-Object { $_.Section -eq $script:Section })
        if ($script:Section -eq 'Tareas') {
            $items = @($items | Where-Object { Test-TaskFilter $_ $filter } |
                Sort-Object @{ Expression = { -not (Test-ActiveTask $_) } }, Title)
            $script:ResourceList.ShowGroups = $false
        } else {
            $items = @($items | Sort-Object Area, Title)
            $script:ResourceList.ShowGroups = ((-not $script:CustomDraw) -and $groupedSection)
        }
        if ($groupedSection) {
            # One header per area, in area order (the list is already sorted by area).
            $areaOrder = [System.Collections.Generic.List[string]]::new()
            $byArea = @{}
            foreach ($resource in $items) {
                $area = if ($resource.Area) { [string]$resource.Area } else { 'Otros' }
                if (-not $byArea.ContainsKey($area)) { $byArea[$area] = [System.Collections.Generic.List[object]]::new(); $areaOrder.Add($area) }
                $byArea[$area].Add($resource)
            }
            foreach ($area in $areaOrder) { Add-ListBlock $area ($byArea[$area].ToArray()) $groups }
        } else {
            foreach ($resource in $items) { Add-ListItem $resource ([string]$resource.Area) $groups }
        }
        $shown = $items.Count
    }
    $script:ResourceList.EndUpdate()
    Update-ListColumns
    $script:ResourceList.Invalidate()
    Update-Layout
    Show-Details $null

    $total = $script:Data.Items.Count
    if ($query -and $shown -eq 0) {
        Set-Status "No hay resultados para «$query». Prueba con otra palabra o pulsa Esc para limpiar."
    } elseif ($query) {
        Set-Status ("{0} resultados de {1} recursos" -f $shown, $total)
    } elseif ($script:Section -eq 'Inicio') {
        Set-Status ("{0} recursos cargados · {1} avisos" -f $total, $script:Data.Warnings.Count)
    } elseif ($shown -eq 0 -and $script:Section -eq 'Tareas') {
        Set-Status 'No hay tareas con este estado. Elige «Todas» en el filtro.'
    } elseif ($shown -eq 0) {
        Set-Status 'No se encontró nada en esta sección.'
    } else {
        Set-Status ("{0} elementos en {1} · {2} recursos en total" -f $shown, $script:Section, $total)
    }
}

function Test-OpenableDocument($Resource) {
    if (-not $Resource -or -not $Resource.Path -or -not $script:Data) { return $false }
    if ([System.IO.Path]::GetExtension($Resource.Path) -ne '.md') { return $false }
    if (-not $Resource.Path.StartsWith($script:Data.WorkshopRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return (Test-Path -LiteralPath $Resource.Path -PathType Leaf)
}

function Get-ResourceFolder($Resource) {
    if (-not $Resource -or -not $Resource.Path -or -not $script:Data) { return '' }
    $folder = $Resource.Path
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { $folder = Split-Path -Parent $folder }
    if (-not (Test-InsideRoot $folder $script:Data.WorkshopRoot)) { return '' }
    return $folder
}

function Show-Details($Resource) {
    # A group header row counts as nothing selected.
    if ($Resource -and [string]$Resource.Section -eq 'Grupo') { $Resource = $null }
    $script:SelectedResource = $Resource
    if ($script:DetailCard) { $script:DetailCard.Invalidate() }
    # Empty state: only a centred message; the content controls appear once something is selected.
    foreach ($control in $script:DetailContent) { $control.Visible = [bool]$Resource }
    $script:EmptyDetailLabel.Visible = (-not $Resource)
    if (-not $Resource) {
        $script:DetailTitle.Text = 'Elige un elemento'
        $script:DetailMeta.Text = ''
        $script:DetailDescription.Text = 'Selecciona un elemento de la lista para ver para qué sirve, cómo usarlo y abrir su documento original.'
        $script:UsageBox.Text = ''
        $script:UsageHint.Text = ''
        $script:RelatedLabel.Text = ''
        $script:CopyButton.Enabled = $false
        $script:OpenButton.Enabled = $false
        $script:FolderButton.Enabled = $false
        Update-Layout
        return
    }
    $script:DetailTitle.Text = $Resource.Title
    $meta = @($Resource.TypeLabel)
    if ($Resource.Section -eq 'Tareas' -and $Resource.Status) { $meta += Get-StatusLabel $Resource.Status }
    elseif ($Resource.Area) { $meta += $Resource.Area }
    if ($Resource.Name -and $Resource.Name -ne $Resource.Title) { $meta += $Resource.Name }
    # The path gets its own line (no word wrap) so it is never broken in the middle of a file name.
    $metaText = ($meta | Where-Object { $_ }) -join '  ·  '
    if ($Resource.RelativePath) { $metaText += "`r`n" + $Resource.RelativePath }
    $script:DetailMeta.Text = $metaText
    $metaLines = if ($Resource.RelativePath) { 2 } else { 1 }
    $script:DetailMeta.Height = $metaLines * $script:DetailMeta.Font.Height + 4
    $script:DetailDescription.Text = if ($Resource.Description) { $Resource.Description } else { 'Este documento no incluye un resumen breve. Ábrelo para leerlo completo.' }
    $script:UsageBox.Text = $Resource.Usage
    $script:UsageHint.Text = $Resource.UsageHint
    $script:CopyButton.Enabled = [bool]$Resource.Usage

    $script:RelatedLabel.Text = ''
    if ($Resource.Section -eq 'Tareas') {
        [object[]]$related = Get-RelatedResources $Resource $script:Data.Items
        $script:RelatedLabel.Text = if ($related.Count -gt 0) {
            'Relacionado: ' + (($related | ForEach-Object { "$($_.Name) ($($_.TypeLabel.ToLowerInvariant()))" }) -join ', ')
        } else { 'Relacionado: esta tarea no menciona agentes ni skills por su nombre.' }
    }
    $script:OpenButton.Enabled = Test-OpenableDocument $Resource
    $folder = Get-ResourceFolder $Resource
    $script:FolderButton.Enabled = [bool]($folder -and (Test-Path -LiteralPath $folder -PathType Container))
    Update-DetailHeights
    Update-Layout
}

# Sizes a read-only text box to its wrapped text, between MinLines and MaxLines; a scroll bar only on overflow.
# Returns the height in pixels for the text area.
function Get-FittedTextHeight($TextBox, [int]$Width, [int]$MinLines, [int]$MaxLines) {
    $font = $TextBox.Font
    $line = $font.Height
    $text = [string]$TextBox.Text
    if (-not $text) { $text = ' ' }
    $flags = [System.Windows.Forms.TextFormatFlags]'WordBreak, TextBoxControl, NoPrefix'
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText($text, $font, [System.Drawing.Size]::new([Math]::Max(40, $Width), [int]::MaxValue), $flags).Height
    $maximum = $line * $MaxLines
    $wanted = if ($measured -gt $maximum) { 'Vertical' } else { 'None' }
    if ([string]$TextBox.ScrollBars -ne $wanted) { $TextBox.ScrollBars = $wanted }
    return [int][Math]::Max($line * $MinLines, [Math]::Min($measured, $maximum))
}

function Update-DetailHeights {
    if (-not $script:SelectedResource -or -not $script:DetailCard) { return }
    $inner = $script:DetailCard.ClientSize.Width - $script:DetailCard.Padding.Horizontal - 4
    if ($inner -lt 120) { return }
    # Description: fits its text, up to 6 lines (keep room for the scroll bar when it overflows).
    $height = Get-FittedTextHeight $script:DetailDescription ($inner - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth) 1 6
    $script:DetailDescription.Height = $height + 6
    # Usage code box: 1 to 3 lines beside the Copiar button.
    $codeWidth = $inner - $script:CopyButton.Width - $script:CopyButton.Margin.Horizontal - $script:UsageCode.Padding.Horizontal - 6
    $usageHeight = Get-FittedTextHeight $script:UsageBox ($codeWidth - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth) 1 3
    $script:UsageCode.Height = [Math]::Max($script:CopyButton.Height, $usageHeight + $script:UsageCode.Padding.Vertical + 4)
}

# Height the detail card needs for its visible content (used for the scrollable minimum).
function Get-DetailNeededHeight {
    $detail = $script:DetailCard
    $rows = @{}
    foreach ($control in $detail.Controls) {
        if ($control -eq $script:EmptyDetailLabel -or -not $control.Visible) { continue }
        $row = $detail.GetRow($control)
        $height = $control.Height + $control.Margin.Vertical
        if (-not $rows.ContainsKey($row) -or $rows[$row] -lt $height) { $rows[$row] = $height }
    }
    $total = $detail.Padding.Vertical + 8
    foreach ($value in $rows.Values) { $total += $value }
    if (-not $script:SelectedResource) { $total = [Math]::Max($total, 180) }
    return $total
}

function Set-Section([string]$Name) {
    $script:Section = $Name
    if ($script:SearchBox.Text) {
        $script:SuppressSearch = $true
        $script:SearchBox.Text = ''
        $script:SuppressSearch = $false
        $script:SearchTimer.Stop()
    }
    Update-NavState
    $script:CategoryTitle.Text = $Name
    $script:IntroLabel.Text = $script:SectionIntros[$Name]
    Render-List
}

function Update-NavState {
    $current = Get-CurrentNav
    foreach ($button in $script:NavButtons) {
        $isSelected = $button.Tag -eq $current
        $button.BackColor = if ($isSelected) { $script:Colors.SidebarSelected } else { $script:Colors.Sidebar }
        $button.ForeColor = if ($isSelected) { $script:Colors.NavSelectedText } else { $script:Colors.SidebarText }
        $button.Font = if ($isSelected) { $script:NavFontSelected } else { $script:NavFont }
        # The marker is visible only with default drawing (high contrast); painted buttons show an accent bar.
        $visible = $button.Text -replace '^▸ ', ''
        $button.Text = if ($isSelected) { '▸ ' + $visible } else { $visible }
        $button.AccessibleName = if ($isSelected) { "$visible, sección actual" } else { $visible }
        $button.Invalidate()
    }
}

function Open-SelectedDocument {
    if (-not (Test-OpenableDocument $script:SelectedResource)) {
        Set-Status 'Este elemento no tiene un documento que se pueda abrir. Pulsa Actualizar (F5) por si ha cambiado.' $true
        return
    }
    try {
        Start-Process -FilePath $script:SelectedResource.Path -ErrorAction Stop
        Set-Status ("Abriendo {0}" -f $script:SelectedResource.RelativePath)
    } catch {
        Set-Status 'No se pudo abrir el documento. Comprueba que Windows tenga una aplicación asociada a los archivos .md.' $true
    }
}

function Open-SelectedFolder {
    $folder = Get-ResourceFolder $script:SelectedResource
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        Set-Status 'La carpeta ya no existe. Pulsa Actualizar (F5).' $true
        return
    }
    try {
        Start-Process -FilePath $folder -ErrorAction Stop
        Set-Status ("Abriendo la carpeta {0}" -f (Get-RelativeWorkshopPath $folder $script:Data.WorkshopRoot))
    } catch {
        Set-Status 'No se pudo abrir la carpeta en el Explorador de archivos.' $true
    }
}

function Copy-Usage {
    if (-not $script:SelectedResource -or -not $script:SelectedResource.Usage) { return }
    try {
        [System.Windows.Forms.Clipboard]::SetText($script:SelectedResource.Usage)
        Set-Status 'Copiado. Pégalo en tu cliente de IA (Ctrl+V).'
    } catch {
        Set-Status 'No se pudo copiar al portapapeles. Selecciona el texto de «Cómo usarlo» y cópialo con Ctrl+C.' $true
    }
}

function Refresh-All {
    $elapsed = Load-Data
    Render-List
    if ($script:Data -and -not $script:SearchBox.Text.Trim() -and $script:Section -eq 'Inicio') {
        Set-Status ("{0} recursos cargados en {1:N1} s · {2} avisos" -f $script:Data.Items.Count, ($elapsed / 1000), $script:Data.Warnings.Count)
    }
}

# Places the detail card beside the list on wide windows and below it on narrow ones, sizes the Inicio
# tiles to the available width, and sets the scrollable minimum so nothing overlaps at 780x560.
function Update-Layout {
    if ($script:InLayout -or -not $script:Body) { return }
    $script:InLayout = $true
    try {
        $contentWidth = [Math]::Max(300, $script:Main.ClientSize.Width - $script:Main.Padding.Horizontal)
        $labelSize = [System.Drawing.Size]::new($contentWidth, 0)
        if ($script:IntroLabel.MaximumSize -ne $labelSize) { $script:IntroLabel.MaximumSize = $labelSize }
        if ($script:TitleRow.Width -ne $contentWidth) { $script:TitleRow.Width = $contentWidth }
        # Each tile carries a 10 px right margin, so seven tiles need seven margins to stay on one row.
        $tileWidth = [int][Math]::Floor(($contentWidth - 7 * 10 - 4) / 7)
        $tileWidth = [Math]::Max(96, [Math]::Min(170, $tileWidth))
        foreach ($tile in $script:Tiles) { if ($tile.Width -ne $tileWidth) { $tile.Width = $tileWidth } }

        # Decide on the outer width, which does not change when scroll bars appear.
        $wide = ($script:MainHost.Width -ge 900)
        # Narrow windows drop the one-line intro to leave room for the list and the detail card.
        if ($script:IntroLabel.Visible -ne $wide) { $script:IntroLabel.Visible = $wide }
        if ($wide -ne $script:WideLayout) {
            $script:WideLayout = $wide
            $body = $script:Body
            $body.SuspendLayout()
            if ($wide) {
                $body.ColumnStyles[0].SizeType = 'Percent'; $body.ColumnStyles[0].Width = 57
                $body.ColumnStyles[1].SizeType = 'Percent'; $body.ColumnStyles[1].Width = 43
                $body.RowStyles[0].SizeType = 'Percent'; $body.RowStyles[0].Height = 100
                $body.RowStyles[1].SizeType = 'Absolute'; $body.RowStyles[1].Height = 0
                $body.SetColumn($script:DetailCard, 1); $body.SetRow($script:DetailCard, 0)
                $script:ListCard.Margin = [System.Windows.Forms.Padding]::new(0, 0, 8, 0)
                $script:DetailCard.Margin = [System.Windows.Forms.Padding]::new(8, 0, 0, 0)
            } else {
                $body.ColumnStyles[0].SizeType = 'Percent'; $body.ColumnStyles[0].Width = 100
                $body.ColumnStyles[1].SizeType = 'Absolute'; $body.ColumnStyles[1].Width = 0
                $body.RowStyles[0].SizeType = 'Percent'; $body.RowStyles[0].Height = 100
                $body.RowStyles[1].SizeType = 'Absolute'; $body.RowStyles[1].Height = 420
                $body.SetColumn($script:DetailCard, 0); $body.SetRow($script:DetailCard, 1)
                $script:ListCard.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 8)
                $script:DetailCard.Margin = [System.Windows.Forms.Padding]::new(0, 8, 0, 0)
            }
            $body.ResumeLayout()
        }

        $top = $script:Main.Padding.Vertical + $script:SearchRow.Height + $script:SearchRow.Margin.Vertical +
            $script:Header.Height + $script:Header.Margin.Vertical
        # The whole detail card (buttons included) must be reachable by scrolling; the list keeps >= 220 px.
        $detailHeight = Get-DetailNeededHeight
        if ($wide) {
            $minimum = [System.Drawing.Size]::new(860, $top + [Math]::Max(300, $detailHeight))
        } else {
            $detailRow = [Math]::Max(220, $detailHeight)
            if ($script:Body.RowStyles[1].Height -ne $detailRow) { $script:Body.RowStyles[1].Height = $detailRow }
            $minimum = [System.Drawing.Size]::new(500, $top + 220 + 16 + $detailRow)
        }
        if ($script:MainHost.AutoScrollMinSize -ne $minimum) { $script:MainHost.AutoScrollMinSize = $minimum }
    } finally {
        $script:InLayout = $false
    }
}

# Wrapping width for the labels inside the detail card.
function Update-DetailWidths {
    $width = [Math]::Max(160, $script:DetailCard.ClientSize.Width - $script:DetailCard.Padding.Horizontal - 4)
    $size = [System.Drawing.Size]::new($width, 0)
    foreach ($label in @($script:DetailTitle, $script:UsageHint, $script:RelatedLabel)) {
        if ($label.MaximumSize -ne $size) { $label.MaximumSize = $size }
    }
    Update-DetailHeights
    Update-Layout
}

# ---------- Window ----------

$script:Form = [System.Windows.Forms.Form]::new()
$script:Form.Text = 'Workshop · Todo lo que tengo'
$script:Form.StartPosition = 'CenterScreen'
$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:Form.Size = [System.Drawing.Size]::new([Math]::Min(1180, $workArea.Width), [Math]::Min(800, $workArea.Height))
$script:Form.MinimumSize = [System.Drawing.Size]::new([Math]::Min(780, $workArea.Width), [Math]::Min(560, $workArea.Height))
$script:Form.BackColor = $script:Colors.Canvas
$script:Form.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$script:Form.KeyPreview = $true

$rootLayout = [System.Windows.Forms.TableLayoutPanel]::new()
$rootLayout.Dock = 'Fill'
$rootLayout.ColumnCount = 2
$rootLayout.RowCount = 2
$rootLayout.Margin = [System.Windows.Forms.Padding]::new(0)
$rootLayout.BackColor = $script:Colors.Canvas
[void]$rootLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute', 214))
[void]$rootLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$rootLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
[void]$rootLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('AutoSize'))
$script:Form.Controls.Add($rootLayout)

# Sidebar (full height, navy): brand, one button per section, infra folder.
$sidebar = [System.Windows.Forms.FlowLayoutPanel]::new()
$sidebar.Dock = 'Fill'
$sidebar.FlowDirection = 'TopDown'
$sidebar.WrapContents = $false
$sidebar.AutoScroll = $true
$sidebar.BackColor = $script:Colors.Sidebar
$sidebar.Padding = [System.Windows.Forms.Padding]::new(14, 18, 10, 12)
$sidebar.Margin = [System.Windows.Forms.Padding]::new(0)
$rootLayout.Controls.Add($sidebar, 0, 0)
$rootLayout.SetRowSpan($sidebar, 2)

$brand = [System.Windows.Forms.Panel]::new()
$brand.Size = [System.Drawing.Size]::new(186, 44)
$brand.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 18)
$brand.BackColor = $script:Colors.Sidebar
$brandMark = [System.Windows.Forms.Label]::new()
$brandMark.Text = 'W'
$brandMark.Size = [System.Drawing.Size]::new(34, 34)
$brandMark.Location = [System.Drawing.Point]::new(0, 5)
$brandMark.TextAlign = 'MiddleCenter'
$brandMark.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 14)
$brandMark.BackColor = $script:Colors.Accent
$brandMark.ForeColor = $script:Colors.ActionText
$brandMark.AccessibleRole = 'Graphic'
$brandMark.AccessibleName = 'Logotipo del Workshop'
$brand.Controls.Add($brandMark)
$sidebarTitle = New-Label 'Workshop' 13 $true
$sidebarTitle.ForeColor = $script:Colors.NavSelectedText
$sidebarTitle.BackColor = $script:Colors.Sidebar
$sidebarTitle.Location = [System.Drawing.Point]::new(42, 1)
$brand.Controls.Add($sidebarTitle)
$sidebarSubtitle = New-Label 'Todo lo que tengo' 8.5
$sidebarSubtitle.ForeColor = $script:Colors.SidebarMuted
$sidebarSubtitle.BackColor = $script:Colors.Sidebar
$sidebarSubtitle.Location = [System.Drawing.Point]::new(43, 24)
$brand.Controls.Add($sidebarSubtitle)
$sidebar.Controls.Add($brand)

$script:NavFont = [System.Drawing.Font]::new('Segoe UI', 10)
$script:NavFontSelected = [System.Drawing.Font]::new('Segoe UI Semibold', 10)
$script:NavButtons = @()
foreach ($name in @('Inicio') + $script:Sections) {
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $name
    $button.Size = [System.Drawing.Size]::new(186, 38)
    $button.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 2)
    $button.FlatStyle = 'Flat'
    $button.TextAlign = 'MiddleLeft'
    $button.Padding = [System.Windows.Forms.Padding]::new(10, 0, 0, 0)
    $button.Cursor = 'Hand'
    $button.Font = $script:NavFont
    $button.AccessibleName = $name
    $button.Tag = $name
    Set-ButtonLook $button $script:Colors.Sidebar $script:Colors.SidebarText $script:Colors.Sidebar 0 $script:Colors.SidebarHover $script:Colors.SidebarAccent
    $button.Add_Click({ param($sender, $eventArgs) Invoke-Safely { Set-Section ([string]$sender.Tag) } })
    if ($script:CustomDraw) {
        Enable-DoubleBuffer $button
        $button.Add_Paint({
            param($sender, $eventArgs)
            try { Draw-NavButton $sender $eventArgs.Graphics } catch { Draw-PlainControl $sender $eventArgs.Graphics }
        })
    }
    Add-FocusCue $button
    $script:NavButtons += $button
    $sidebar.Controls.Add($button)
}

# Folder caption and path use the light sidebar text (11.1:1 on navy).
$rootLabel = New-Label 'CARPETA INFRA' 8.5 $true
$rootLabel.ForeColor = $script:Colors.SidebarText
$rootLabel.Margin = [System.Windows.Forms.Padding]::new(2, 22, 0, 4)
$sidebar.Controls.Add($rootLabel)
$script:RootPathLabel = New-Label '' 9
$script:RootPathLabel.ForeColor = $script:Colors.SidebarText
$script:RootPathLabel.MaximumSize = [System.Drawing.Size]::new(184, 0)
$script:RootPathLabel.Margin = [System.Windows.Forms.Padding]::new(2, 0, 0, 8)
$sidebar.Controls.Add($script:RootPathLabel)
$chooseRootButton = New-FlatButton 'Elegir carpeta…' 'Elegir la carpeta infra del Workshop'
$chooseRootButton.MinimumSize = [System.Drawing.Size]::new(186, 34)
$chooseRootButton.Font = [System.Drawing.Font]::new('Segoe UI', 9.5)
# Border in SidebarMuted: 6.3:1 against navy, 5.1:1 against the button fill.
Set-ButtonLook $chooseRootButton $script:Colors.SidebarHover $script:Colors.SidebarText $script:Colors.SidebarMuted 1 $script:Colors.SidebarSelected $script:Colors.SidebarAccent
$sidebar.Controls.Add($chooseRootButton)

# Main area: search bar, header (title, intro, tiles, filter), then the list and detail cards.
$main = [System.Windows.Forms.TableLayoutPanel]::new()
$main.Dock = 'Fill'
$main.ColumnCount = 1
$main.RowCount = 3
$main.Padding = [System.Windows.Forms.Padding]::new(24, 18, 24, 14)
$main.BackColor = $script:Colors.Canvas
[void]$main.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new('AutoSize'))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new('AutoSize'))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
$mainHost = [System.Windows.Forms.Panel]::new()
$mainHost.Dock = 'Fill'
$mainHost.AutoScroll = $true
$mainHost.AutoScrollMinSize = [System.Drawing.Size]::new(540, 700)
$mainHost.Margin = [System.Windows.Forms.Padding]::new(0)
$mainHost.BackColor = $script:Colors.Canvas
$mainHost.Controls.Add($main)
$rootLayout.Controls.Add($mainHost, 1, 0)
$script:Main = $main
$script:MainHost = $mainHost

# Search: a rounded white field with a magnifier, a borderless text box and a hint shown while it is empty.
$searchRow = [System.Windows.Forms.TableLayoutPanel]::new()
$searchRow.Dock = 'Top'
$searchRow.AutoSize = $true
$searchRow.ColumnCount = 2
$searchRow.RowCount = 1
$searchRow.BackColor = $script:Colors.Canvas
[void]$searchRow.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$searchRow.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('AutoSize'))
$searchRow.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 16)
$script:SearchRow = $searchRow
$script:SearchCard = [System.Windows.Forms.Panel]::new()
$script:SearchCard.Height = 42
$script:SearchCard.Anchor = 'Left, Right'
$script:SearchCard.Margin = [System.Windows.Forms.Padding]::new(0)
$script:SearchCard.BackColor = $script:Colors.White
$script:SearchCard.Padding = [System.Windows.Forms.Padding]::new(38, 11, 12, 0)
$script:SearchCard.Cursor = 'IBeam'
if (-not $script:CustomDraw) {
    $script:SearchCard.Padding = [System.Windows.Forms.Padding]::new(6, 8, 6, 0)
    $script:SearchCard.BorderStyle = 'FixedSingle'
}
Add-CardPaint $script:SearchCard
$script:SearchBox = [System.Windows.Forms.TextBox]::new()
$script:SearchBox.Dock = 'Top'
$script:SearchBox.BorderStyle = 'None'
$script:SearchBox.BackColor = $script:Colors.White
$script:SearchBox.ForeColor = $script:Colors.Ink
$script:SearchBox.Font = [System.Drawing.Font]::new('Segoe UI', 11)
$script:SearchBox.AccessibleName = 'Buscar en todo el Workshop por nombre, descripción o área'
$script:SearchCard.Controls.Add($script:SearchBox)
# The hint starts a few pixels right of the caret so the caret stays visible while the box is empty.
$script:SearchCard.Width = 600
$script:SearchHint = New-Label 'Buscar en todo el Workshop: nombre, descripción o área   (Ctrl+F)' 11
$script:SearchHint.ForeColor = $script:Colors.Muted
$script:SearchHint.BackColor = $script:Colors.White
$script:SearchHint.AutoSize = $false
$script:SearchHint.AutoEllipsis = $true
$script:SearchHint.Location = [System.Drawing.Point]::new($script:SearchCard.Padding.Left + 4, $script:SearchCard.Padding.Top)
$script:SearchHint.Size = [System.Drawing.Size]::new($script:SearchCard.Width - $script:SearchCard.Padding.Horizontal - 8, 22)
$script:SearchHint.Anchor = 'Top, Left, Right'
$script:SearchHint.Cursor = 'IBeam'
$script:SearchCard.Controls.Add($script:SearchHint)
$script:SearchHint.BringToFront()
$script:SearchHint.Add_Click({ $script:SearchBox.Focus() })
$script:SearchCard.Add_Click({ $script:SearchBox.Focus() })
$searchRow.Controls.Add($script:SearchCard, 0, 0)
$refreshButton = New-FlatButton 'Actualizar' 'Volver a leer todos los recursos (F5)'
$refreshButton.MinimumSize = [System.Drawing.Size]::new(112, 42)
$refreshButton.Margin = [System.Windows.Forms.Padding]::new(12, 0, 0, 0)
$searchRow.Controls.Add($refreshButton, 1, 0)
$main.Controls.Add($searchRow, 0, 0)

$header = [System.Windows.Forms.FlowLayoutPanel]::new()
$header.Dock = 'Top'
$header.AutoSize = $true
$header.FlowDirection = 'TopDown'
$header.WrapContents = $false
$header.BackColor = $script:Colors.Canvas
$header.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 14)
$script:Header = $header
# Title row: section title on the left, the Estado filter on the right (fixed height, so the list top
# does not move when the filter appears or disappears).
$script:TitleRow = [System.Windows.Forms.TableLayoutPanel]::new()
$script:TitleRow.ColumnCount = 2
$script:TitleRow.RowCount = 1
$script:TitleRow.Size = [System.Drawing.Size]::new(600, 44)
$script:TitleRow.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 2)
$script:TitleRow.BackColor = $script:Colors.Canvas
[void]$script:TitleRow.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$script:TitleRow.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('AutoSize'))
[void]$script:TitleRow.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
$header.Controls.Add($script:TitleRow)
$script:CategoryTitle = New-Label 'Inicio' 20 $true
$script:CategoryTitle.Anchor = 'Left'
$script:CategoryTitle.AutoEllipsis = $true
$script:CategoryTitle.Margin = [System.Windows.Forms.Padding]::new(0)
$script:TitleRow.Controls.Add($script:CategoryTitle, 0, 0)
$script:IntroLabel = New-Label '' 10
$script:IntroLabel.ForeColor = $script:Colors.Muted
$script:IntroLabel.Margin = [System.Windows.Forms.Padding]::new(1, 0, 0, 2)
$header.Controls.Add($script:IntroLabel)

# Inicio tiles: painted cards with a big number, a label and a stripe in the type colour.
$script:TilePanel = [System.Windows.Forms.FlowLayoutPanel]::new()
$script:TilePanel.AutoSize = $true
$script:TilePanel.WrapContents = $true
$script:TilePanel.BackColor = $script:Colors.Canvas
$script:TilePanel.Margin = [System.Windows.Forms.Padding]::new(0, 12, 0, 0)
$script:Tiles = @()
foreach ($name in $script:Sections) {
    $tile = [System.Windows.Forms.Button]::new()
    $tile.Tag = $name
    $tile.Text = $name
    $tile.Size = [System.Drawing.Size]::new(124, 74)
    $tile.Margin = [System.Windows.Forms.Padding]::new(0, 0, 10, 10)
    $tile.FlatStyle = 'Flat'
    $tile.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 9.5)
    $tile.Cursor = 'Hand'
    Set-ButtonLook $tile $script:Colors.White $script:Colors.Ink $script:Colors.Line 1 $script:Colors.RowHover $script:Colors.Accent
    $tile.Add_Click({ param($sender, $eventArgs) Invoke-Safely { Set-Section ([string]$sender.Tag) } })
    if ($script:CustomDraw) {
        Enable-DoubleBuffer $tile
        $tile.Add_Paint({
            param($sender, $eventArgs)
            try { Draw-Tile $sender $eventArgs.Graphics } catch { Draw-PlainControl $sender $eventArgs.Graphics }
        })
    }
    Add-FocusCue $tile
    $script:Tiles += $tile
    $script:TilePanel.Controls.Add($tile)
}
$header.Controls.Add($script:TilePanel)

$filterRow = [System.Windows.Forms.FlowLayoutPanel]::new()
$filterRow.AutoSize = $true
$filterRow.WrapContents = $false
$filterRow.Anchor = 'Right'
$filterRow.BackColor = $script:Colors.Canvas
$filterRow.Margin = [System.Windows.Forms.Padding]::new(12, 0, 0, 0)
$script:FilterLabel = New-Label 'Estado:' 10 $true
$script:FilterLabel.Margin = [System.Windows.Forms.Padding]::new(0, 5, 8, 0)
$filterRow.Controls.Add($script:FilterLabel)
$script:StatusFilter = [System.Windows.Forms.ComboBox]::new()
$script:StatusFilter.DropDownStyle = 'DropDownList'
$script:StatusFilter.Items.AddRange([object[]]$script:TaskFilters)
$script:StatusFilter.SelectedIndex = 0
$script:StatusFilter.Width = 220
$script:StatusFilter.AccessibleName = 'Filtrar tareas por estado'
$filterRow.Controls.Add($script:StatusFilter)
$script:TitleRow.Controls.Add($filterRow, 1, 0)
$main.Controls.Add($header, 0, 1)

# Body: list card and detail card; Update-Layout puts them side by side or stacked.
$body = [System.Windows.Forms.TableLayoutPanel]::new()
$body.Dock = 'Fill'
$body.ColumnCount = 2
$body.RowCount = 2
$body.Margin = [System.Windows.Forms.Padding]::new(0)
$body.BackColor = $script:Colors.Canvas
[void]$body.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 57))
[void]$body.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 43))
[void]$body.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
[void]$body.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 0))
$main.Controls.Add($body, 0, 2)

$script:ListCard = [System.Windows.Forms.Panel]::new()
$script:ListCard.Dock = 'Fill'
$script:ListCard.BackColor = $script:Colors.White
$script:ListCard.Padding = [System.Windows.Forms.Padding]::new(2, 6, 2, 6)
if (-not $script:CustomDraw) { $script:ListCard.Padding = [System.Windows.Forms.Padding]::new(0) }
Add-CardPaint $script:ListCard
$body.Controls.Add($script:ListCard, 0, 0)

$script:ResourceList = [System.Windows.Forms.ListView]::new()
$script:ResourceList.View = 'Details'
$script:ResourceList.FullRowSelect = $true
$script:ResourceList.MultiSelect = $false
$script:ResourceList.HideSelection = $false
$script:ResourceList.ShowItemToolTips = $true
$script:ResourceList.HeaderStyle = 'Nonclickable'
$script:ResourceList.Dock = 'Fill'
$script:ResourceList.Margin = [System.Windows.Forms.Padding]::new(0)
$script:ResourceList.Font = [System.Drawing.Font]::new('Segoe UI', 10)
[void]$script:ResourceList.Columns.Add('Nombre', 380)
[void]$script:ResourceList.Columns.Add('Tipo', 128)
[void]$script:ResourceList.Columns.Add('Detalle', 220)
$script:ResourceList.AccessibleName = 'Lista de recursos. Pulsa Intro para abrir el documento seleccionado'
$script:ResourceList.BackColor = $script:Colors.White
$script:ResourceList.ForeColor = $script:Colors.Ink
if ($script:CustomDraw) {
    # Owner-drawn rows: title plus one-line description, type and status badges, separators.
    $script:ResourceList.BorderStyle = 'None'
    $script:ResourceList.OwnerDraw = $true
    $rowHeight = [System.Windows.Forms.ImageList]::new()
    $rowHeight.ImageSize = [System.Drawing.Size]::new(1, 50)   # the only way to set row height in a ListView
    $script:ResourceList.SmallImageList = $rowHeight
    Enable-DoubleBuffer $script:ResourceList
}
$script:ListCard.Controls.Add($script:ResourceList)

# Detail card: title, meta, description, «Cómo usarlo» code box with Copiar, hint, related, actions.
$detail = [System.Windows.Forms.TableLayoutPanel]::new()
$detail.Dock = 'Fill'
$detail.ColumnCount = 2
$detail.RowCount = 10
$detail.BackColor = $script:Colors.White
$detail.Padding = [System.Windows.Forms.Padding]::new(20, 18, 20, 14)
$detail.Margin = [System.Windows.Forms.Padding]::new(8, 0, 0, 0)
$detail.CellBorderStyle = 'None'
if (-not $script:CustomDraw) { $detail.BorderStyle = 'FixedSingle' }
[void]$detail.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$detail.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('AutoSize'))
# Rows: title, meta, caption, description, caption, code box + Copiar, hint, related, spacer (empty-state
# message), actions. Only the spacer stretches, so the actions sit at the bottom of the card.
foreach ($style in @('AutoSize', 'AutoSize', 'AutoSize', 'AutoSize', 'AutoSize', 'AutoSize', 'AutoSize', 'AutoSize', 'Percent', 'AutoSize')) {
    if ($style -eq 'Percent') { [void]$detail.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100)) }
    else { [void]$detail.RowStyles.Add([System.Windows.Forms.RowStyle]::new('AutoSize')) }
}
$script:DetailCard = $detail
Add-CardPaint $detail
$body.Controls.Add($detail, 1, 0)
$script:Body = $body

$script:DetailTitle = New-Label 'Elige un elemento' 13 $true
$script:DetailTitle.AutoEllipsis = $true
$script:DetailTitle.Anchor = 'Left'
$script:DetailTitle.MaximumSize = [System.Drawing.Size]::new(360, 0)
$script:DetailTitle.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 2)
$detail.Controls.Add($script:DetailTitle, 0, 0)
$detail.SetColumnSpan($script:DetailTitle, 2)
$script:DetailMeta = [System.Windows.Forms.TextBox]::new()
$script:DetailMeta.ReadOnly = $true
$script:DetailMeta.Multiline = $true
$script:DetailMeta.WordWrap = $false
$script:DetailMeta.Height = 34
$script:DetailMeta.BorderStyle = 'None'
$script:DetailMeta.BackColor = $script:Colors.White
$script:DetailMeta.ForeColor = $script:Colors.Muted
$script:DetailMeta.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$script:DetailMeta.Dock = 'Fill'
$script:DetailMeta.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 4)
$script:DetailMeta.AccessibleName = 'Tipo, estado y ubicación del elemento'
$script:DetailMeta.TabStop = $false
$detail.Controls.Add($script:DetailMeta, 0, 1)
$detail.SetColumnSpan($script:DetailMeta, 2)
$purposeLabel = New-Label 'PARA QUÉ SIRVE' 8 $true
$script:PurposeLabel = $purposeLabel
$purposeLabel.ForeColor = $script:Colors.Muted
$purposeLabel.Margin = [System.Windows.Forms.Padding]::new(0, 4, 0, 4)
$detail.Controls.Add($purposeLabel, 0, 2)
$detail.SetColumnSpan($purposeLabel, 2)
$script:DetailDescription = [System.Windows.Forms.TextBox]::new()
$script:DetailDescription.Multiline = $true
$script:DetailDescription.ReadOnly = $true
$script:DetailDescription.ScrollBars = 'Vertical'
$script:DetailDescription.BorderStyle = 'None'
if (-not $script:CustomDraw) { $script:DetailDescription.BorderStyle = 'FixedSingle' }
$script:DetailDescription.BackColor = $script:Colors.White
$script:DetailDescription.ForeColor = $script:Colors.Ink
$script:DetailDescription.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$script:DetailDescription.Dock = 'Fill'
$script:DetailDescription.Height = 60   # Update-DetailHeights fits it to the text (up to 6 lines)
$script:DetailDescription.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 8)
$script:DetailDescription.AccessibleName = 'Para qué sirve'
$detail.Controls.Add($script:DetailDescription, 0, 3)
$detail.SetColumnSpan($script:DetailDescription, 2)
$script:UsageLabel = New-Label 'CÓMO USARLO' 8 $true
$script:UsageLabel.ForeColor = $script:Colors.Muted
$script:UsageLabel.Margin = [System.Windows.Forms.Padding]::new(0, 10, 0, 6)
$detail.Controls.Add($script:UsageLabel, 0, 4)
$detail.SetColumnSpan($script:UsageLabel, 2)
# Code-like box: tinted rounded panel around a borderless monospace text box.
$script:UsageCode = [System.Windows.Forms.Panel]::new()
$script:UsageCode.Height = 60
$script:UsageCode.Dock = 'Fill'
$script:UsageCode.BackColor = $script:Colors.Canvas
$script:UsageCode.Padding = [System.Windows.Forms.Padding]::new(10, 8, 6, 6)
$script:UsageCode.Margin = [System.Windows.Forms.Padding]::new(0)
if (-not $script:CustomDraw) {
    $script:UsageCode.Padding = [System.Windows.Forms.Padding]::new(0)
    $script:UsageCode.BorderStyle = 'FixedSingle'
}
Add-CardPaint $script:UsageCode
$script:UsageBox = [System.Windows.Forms.TextBox]::new()
$script:UsageBox.Multiline = $true
$script:UsageBox.ReadOnly = $true
$script:UsageBox.ScrollBars = 'Vertical'
$script:UsageBox.BorderStyle = 'None'
$script:UsageBox.Dock = 'Fill'
$script:UsageBox.BackColor = $script:Colors.Canvas
$script:UsageBox.ForeColor = $script:Colors.Ink
$script:UsageBox.Font = [System.Drawing.Font]::new('Consolas', 10)
$script:UsageBox.AccessibleName = 'Cómo usarlo: texto para pegar en tu cliente de IA'
$script:UsageCode.Controls.Add($script:UsageBox)
$detail.Controls.Add($script:UsageCode, 0, 5)
$script:CopyButton = New-FlatButton 'Copiar' 'Copiar el texto de cómo usarlo al portapapeles'
$script:CopyButton.MinimumSize = [System.Drawing.Size]::new(92, 36)
$script:CopyButton.Margin = [System.Windows.Forms.Padding]::new(10, 0, 0, 0)
$script:CopyButton.Anchor = 'Top'
$detail.Controls.Add($script:CopyButton, 1, 5)
$script:UsageHint = New-Label '' 9
$script:UsageHint.ForeColor = $script:Colors.Muted
$script:UsageHint.Margin = [System.Windows.Forms.Padding]::new(0, 6, 0, 2)
$detail.Controls.Add($script:UsageHint, 0, 6)
$detail.SetColumnSpan($script:UsageHint, 2)
$script:RelatedLabel = New-Label '' 9
$script:RelatedLabel.ForeColor = $script:Colors.Muted
$script:RelatedLabel.Margin = [System.Windows.Forms.Padding]::new(0, 4, 0, 4)
$detail.Controls.Add($script:RelatedLabel, 0, 7)
$detail.SetColumnSpan($script:RelatedLabel, 2)
$actions = [System.Windows.Forms.FlowLayoutPanel]::new()
$actions.AutoSize = $true
$actions.Dock = 'Fill'
$actions.FlowDirection = 'RightToLeft'
$actions.WrapContents = $false
$actions.BackColor = $script:Colors.White
$actions.Margin = [System.Windows.Forms.Padding]::new(0, 8, 0, 0)
$script:OpenButton = New-FlatButton 'Abrir documento' 'Abrir el documento original en su editor (Intro)' $true
$script:OpenButton.Margin = [System.Windows.Forms.Padding]::new(0)
$script:FolderButton = New-FlatButton 'Abrir carpeta' 'Abrir la carpeta del elemento en el Explorador de archivos'
$script:FolderButton.Margin = [System.Windows.Forms.Padding]::new(0, 0, 10, 0)
$actions.Controls.Add($script:OpenButton)
$actions.Controls.Add($script:FolderButton)
$detail.Controls.Add($actions, 0, 9)
$detail.SetColumnSpan($actions, 2)

# Empty state: one friendly, centred message in the stretching row.
$script:EmptyDetailLabel = New-Label 'Selecciona algo de la lista para ver qué es y cómo usarlo.' 10.5
$script:EmptyDetailLabel.AutoSize = $false
$script:EmptyDetailLabel.Dock = 'Fill'
$script:EmptyDetailLabel.TextAlign = 'MiddleCenter'
$script:EmptyDetailLabel.ForeColor = $script:Colors.Muted
$script:EmptyDetailLabel.Margin = [System.Windows.Forms.Padding]::new(0)
$detail.Controls.Add($script:EmptyDetailLabel, 0, 8)
$detail.SetColumnSpan($script:EmptyDetailLabel, 2)
$script:DetailContent = @($script:DetailTitle, $script:DetailMeta, $script:PurposeLabel, $script:DetailDescription,
    $script:UsageLabel, $script:UsageCode, $script:CopyButton, $script:UsageHint, $script:RelatedLabel, $actions)

$script:StatusLabel = [System.Windows.Forms.Label]::new()
$script:StatusLabel.Text = 'Cargando…'
$script:StatusLabel.Dock = 'Fill'
$script:StatusLabel.AutoSize = $false
$script:StatusLabel.Height = 28
$script:StatusLabel.AccessibleRole = 'StatusBar'
$script:StatusLabel.TextAlign = 'MiddleLeft'
$script:StatusLabel.UseMnemonic = $false
$script:StatusLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$script:StatusLabel.Padding = [System.Windows.Forms.Padding]::new(24, 0, 0, 0)
$script:StatusLabel.Margin = [System.Windows.Forms.Padding]::new(0)
$script:StatusLabel.BackColor = $script:Colors.White
$script:StatusLabel.ForeColor = $script:Colors.Muted
if ($script:CustomDraw) {
    $script:StatusLabel.Add_Paint({
        param($sender, $eventArgs)
        try { $eventArgs.Graphics.FillRectangle((Get-Brush $script:Colors.Line), 0, 0, $sender.Width, 1) } catch { }
    })
}
$rootLayout.Controls.Add($script:StatusLabel, 1, 1)

# Keyboard order: sections and folder chooser, then search, refresh, tiles and filter, list, detail.
$tabOrder = @($script:SearchBox, $refreshButton) + $script:NavButtons + @($script:TilePanel, $filterRow, $script:ResourceList,
    $script:DetailMeta, $script:DetailDescription, $script:UsageBox, $script:CopyButton, $script:OpenButton, $script:FolderButton, $chooseRootButton)
for ($index = 0; $index -lt $tabOrder.Count; $index++) { $tabOrder[$index].TabIndex = $index }
$sidebar.TabIndex = 0
$mainHost.TabIndex = 1
$searchRow.TabIndex = 0
$header.TabIndex = 1
$body.TabIndex = 2
$script:SearchCard.TabIndex = 0
$refreshButton.TabIndex = 1
$script:ListCard.TabIndex = 0
$detail.TabIndex = 1
$script:TitleRow.TabIndex = $filterRow.TabIndex
$script:UsageCode.TabIndex = $script:UsageBox.TabIndex
$actions.TabIndex = $script:OpenButton.TabIndex

# ---------- Events ----------

$script:SearchTimer = [System.Windows.Forms.Timer]::new()
$script:SearchTimer.Interval = 250
$script:SearchTimer.Add_Tick({ $script:SearchTimer.Stop(); Invoke-Safely { Render-List } })
$script:SuppressSearch = $false
$script:SearchBox.Add_TextChanged({ if (-not $script:SuppressSearch) { $script:SearchTimer.Stop(); $script:SearchTimer.Start() } })
$script:SearchBox.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq 'Escape' -and $script:SearchBox.Text) {
        $script:SearchBox.Text = ''
        $eventArgs.SuppressKeyPress = $true
    } elseif ($eventArgs.KeyCode -in @('Down', 'Enter') -and $script:ResourceList.Items.Count -gt 0) {
        $script:SearchTimer.Stop()
        Invoke-Safely { Render-List }
        [void]$script:ResourceList.Focus()
        Invoke-Safely { [void](Select-FirstResource) }
        $eventArgs.SuppressKeyPress = $true
    }
})
$script:StatusFilter.Add_SelectedIndexChanged({ Invoke-Safely { Render-List } })
$refreshButton.Add_Click({ Invoke-Safely { Refresh-All } })
$script:ResourceList.Add_SelectedIndexChanged({
    Invoke-Safely {
        if ($script:ResourceList.SelectedItems.Count -gt 0) { Show-Details $script:ResourceList.SelectedItems[0].Tag }
        else { Show-Details $null }
    }
})
$script:ResourceList.Add_ItemActivate({
    Invoke-Safely {
        # Enter on a group header does nothing.
        if ($script:ResourceList.SelectedItems.Count -gt 0 -and (Test-HeaderItem $script:ResourceList.SelectedItems[0])) { return }
        Open-SelectedDocument
    }
})
$script:ResourceList.Add_GotFocus({
    if ($script:ResourceList.SelectedItems.Count -eq 0 -and $script:ResourceList.Items.Count -gt 0) {
        Invoke-Safely { [void](Select-FirstResource) }
    }
})
$script:ResourceList.Add_Resize({ Invoke-Safely { Update-ListColumns } })
$main.Add_Resize({ Invoke-Safely { Update-Layout } })
$mainHost.Add_Resize({ Invoke-Safely { Update-Layout } })
$header.Add_SizeChanged({ Invoke-Safely { Update-Layout } })
$detail.Add_Resize({ Invoke-Safely { Update-DetailWidths } })

# Search hint (placeholder) is shown while the box is empty; focus repaints the search card ring.
$script:SearchBox.Add_TextChanged({ $script:SearchHint.Visible = (-not $script:SearchBox.Text) })
$script:SearchBox.Add_GotFocus({ $script:SearchCard.Invalidate() })
$script:SearchBox.Add_LostFocus({ $script:SearchCard.Invalidate() })
$script:UsageBox.Add_GotFocus({ $script:UsageCode.Invalidate() })
$script:UsageBox.Add_LostFocus({ $script:UsageCode.Invalidate() })

# Owner drawing of the list. Any failure falls back to default drawing instead of crashing the window.
if ($script:CustomDraw) {
    $script:ResourceList.Add_DrawColumnHeader({
        param($sender, $eventArgs)
        try { Draw-ListHeader $eventArgs } catch { $eventArgs.DrawDefault = $true }
    })
    $script:ResourceList.Add_DrawItem({
        param($sender, $eventArgs)
        try {
            if ($null -eq $eventArgs.Item) { $eventArgs.DrawDefault = $true; return }
            $eventArgs.Graphics.FillRectangle((Get-Brush (Get-RowBack $eventArgs.Item $eventArgs.ItemIndex)), $eventArgs.Bounds)
        } catch { $eventArgs.DrawDefault = $true }
    })
    $script:ResourceList.Add_DrawSubItem({
        param($sender, $eventArgs)
        try {
            if ($null -eq $eventArgs.Item) { $eventArgs.DrawDefault = $true; return }
            Draw-ListCell $eventArgs
        } catch { $eventArgs.DrawDefault = $true }
    })
    # Hover highlight; repainting the hovered row also avoids a known owner-draw glitch on mouse-over.
    $script:ResourceList.Add_MouseMove({
        param($sender, $eventArgs)
        try {
            $hit = $script:ResourceList.GetItemAt($eventArgs.X, $eventArgs.Y)
            Set-HoverIndex $(if ($hit) { $hit.Index } else { -1 })
        } catch { }
    })
    $script:ResourceList.Add_MouseLeave({ try { Set-HoverIndex -1 } catch { } })
    $script:ResourceList.Add_GotFocus({ $script:ResourceList.Invalidate(); $script:ListCard.Invalidate() })
    $script:ResourceList.Add_LostFocus({ $script:ResourceList.Invalidate(); $script:ListCard.Invalidate() })
}
$script:CopyButton.Add_Click({ Invoke-Safely { Copy-Usage } })
$script:OpenButton.Add_Click({ Invoke-Safely { Open-SelectedDocument } })
$script:FolderButton.Add_Click({ Invoke-Safely { Open-SelectedFolder } })
$chooseRootButton.Add_Click({
    Invoke-Safely {
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Selecciona la carpeta infra del Workshop (la que contiene tasks, agents y docs).'
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            if ((Test-Path -LiteralPath (Join-Path $dialog.SelectedPath 'tasks') -PathType Container) -and
                (Test-Path -LiteralPath (Join-Path $dialog.SelectedPath 'agents') -PathType Container)) {
                $script:InfraRoot = [System.IO.Path]::GetFullPath($dialog.SelectedPath)
                Refresh-All
            } else {
                Set-Status 'Esa no es la carpeta infra del Workshop: debe contener las subcarpetas «tasks» (tareas) y «agents» (agentes).' $true
            }
        }
    }
})
$script:Form.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Control -and $eventArgs.KeyCode -eq 'F') {
        $script:SearchBox.Focus()
        $script:SearchBox.SelectAll()
        $eventArgs.SuppressKeyPress = $true
    } elseif ($eventArgs.KeyCode -eq 'Escape' -and $script:SearchBox.Text) {
        $script:SearchBox.Text = ''
        $script:SearchBox.Focus()
        $eventArgs.SuppressKeyPress = $true
    } elseif ($eventArgs.KeyCode -eq 'F5') {
        Invoke-Safely { Refresh-All }
        $eventArgs.SuppressKeyPress = $true
    }
})

# Smoke test: visit every section, search, select an item, then close and report on stdout.
# Design review aid: when WORKSHOP_UI_SCREENSHOT_DIR is set, save PNGs of key screens there and close.
function Save-Screen([string]$Folder, [string]$Name) {
    [System.Windows.Forms.Application]::DoEvents()
    $bitmap = [System.Drawing.Bitmap]::new($script:Form.Width, $script:Form.Height)
    try {
        $script:Form.DrawToBitmap($bitmap, [System.Drawing.Rectangle]::new(0, 0, $script:Form.Width, $script:Form.Height))
        $bitmap.Save((Join-Path $Folder "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
}

function Invoke-Screenshots([string]$Folder) {
    Set-Section 'Inicio'
    Save-Screen $Folder '1-inicio'
    Set-Section 'Agentes'
    [void](Select-ResourceAt 3)
    Save-Screen $Folder '2-agentes'
    Set-Section 'Tareas'
    [void](Select-FirstResource)
    Save-Screen $Folder '3-tareas'
    $script:SearchBox.Text = 'seguridad'
    $script:SearchTimer.Stop()
    Render-List
    [void](Select-FirstResource)
    Save-Screen $Folder '4-busqueda'
    $script:Form.Size = $script:Form.MinimumSize
    Set-Section 'Aplicaciones'
    [void](Select-FirstResource)
    Save-Screen $Folder '5-ventana-minima'
}

# Counts below are real resources only; owner-drawn group header rows are skipped.
function Invoke-SmokeTest {
    $report = [System.Collections.Generic.List[string]]::new()
    $report.Add("loaded=$($script:Data.Items.Count) warnings=$($script:Data.Warnings.Count)")
    foreach ($name in @('Inicio') + $script:Sections) {
        Set-Section $name
        if ($name -eq 'Tareas') { $script:StatusFilter.SelectedIndex = 1 }
        $report.Add("section[$name]=$(@(Get-ResourceItems).Count)")
        if (Select-FirstResource) {
            [System.Windows.Forms.Application]::DoEvents()
            $report.Add("detail[$name]=$($script:DetailTitle.Text) | usage=$($script:UsageBox.Text -replace "`r`n", ' / ') | open=$($script:OpenButton.Enabled)")
        }
    }
    Set-Section 'Tareas'
    $script:StatusFilter.SelectedIndex = 1
    $taskItems = @(Get-ResourceItems)
    foreach ($item in $taskItems) {
        $item.Selected = $true
        [System.Windows.Forms.Application]::DoEvents()
    }
    $thirdColumn = if ($taskItems.Count -gt 0) { $taskItems[0].SubItems[2].Text } else { '' }
    $report.Add("tasks-selected=$($taskItems.Count) third-column=$thirdColumn")
    $script:StatusFilter.SelectedIndex = 0
    $script:SearchBox.Text = 'ui'
    Render-List
    $report.Add("search[ui]=$(@(Get-ResourceItems).Count) filter-visible=$($script:StatusFilter.Visible)")
    $script:SearchBox.Text = 'revisor seguridad'
    Render-List
    $report.Add("search[revisor seguridad]=$(@(Get-ResourceItems).Count)")
    $script:SearchBox.Text = 'security'
    Render-List
    $report.Add("search[security]=$(@(Get-ResourceItems).Count) status=$($script:StatusLabel.Text)")
    $report.Add("errors=$($script:SmokeErrors.Count) $($script:SmokeErrors -join ' | ')")
    [Console]::Out.WriteLine(($report -join [Environment]::NewLine))
}

$script:Form.Add_Shown({
    Invoke-Safely { Update-Layout; Update-DetailWidths }
    Invoke-Safely { Load-Data; Set-Section 'Inicio' }
    if ($script:Data) {
        Set-Status ("{0} recursos cargados · {1} avisos · Ctrl+F para buscar, F5 para actualizar" -f $script:Data.Items.Count, $script:Data.Warnings.Count)
    }
    $script:SearchBox.Focus()
    if ($env:WORKSHOP_UI_SCREENSHOT_DIR -and (Test-Path -LiteralPath $env:WORKSHOP_UI_SCREENSHOT_DIR -PathType Container)) {
        Invoke-Safely { Invoke-Screenshots $env:WORKSHOP_UI_SCREENSHOT_DIR }
        $script:Form.Close()
    } elseif ($script:SmokeTest) {
        Invoke-Safely { Invoke-SmokeTest }
        $script:Form.Close()
    }
})

[System.Windows.Forms.Application]::Run($script:Form)
if ($script:SmokeTest -and $script:SmokeErrors.Count -gt 0) { exit 1 }
