$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing.Common

$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$OutDir = Join-Path $Root "reports\paper_elec_s_37_results_ready_336h_0301_1601"

function New-Canvas($path, $width, $height, [scriptblock]$draw) {
    $bmp = [System.Drawing.Bitmap]::new($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::White)
    & $draw $g
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

function Quantiles([double[]]$values) {
    $v = @($values | Sort-Object)
    $n = $v.Count
    $out = @()
    foreach ($p in @(0.0, 0.25, 0.5, 0.75, 1.0)) {
        $idx = [Math]::Max(0, [Math]::Min($n - 1, [int][Math]::Floor($p * ($n - 1) + 0.5)))
        $out += [double]$v[$idx]
    }
    return $out
}

$fontTitle = [System.Drawing.Font]::new("Arial", 16, [System.Drawing.FontStyle]::Bold)
$font = [System.Drawing.Font]::new("Arial", 9)
$fontSmall = [System.Drawing.Font]::new("Arial", 8)
$black = [System.Drawing.Brushes]::Black
$blue = [System.Drawing.Brushes]::SteelBlue
$red = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(190, 204, 102, 119))
$gold = [System.Drawing.Brushes]::Khaki
$pen = [System.Drawing.Pen]::new([System.Drawing.Color]::Black, 1)
$zeroPen = [System.Drawing.Pen]::new([System.Drawing.Color]::DimGray, 1)
$zeroPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

$binding = Import-Csv (Join-Path $OutDir "figure_binding_data.csv")
New-Canvas (Join-Path $OutDir "figure_binding.png") 1100 780 {
    param($g)
    $g.DrawString("Binding frequency and GFM-BESS deployment (gSCR-GERSH)", $fontTitle, $black, 245, 18)
    $left = 230; $top = 58; $rowh = 18; $barw = 650
    $maxBeta = ($binding | ForEach-Object {[double]$_.beta_i} | Measure-Object -Maximum).Maximum
    $maxCap = ($binding | ForEach-Object {[double]$_.gfm_bess_capacity_GW} | Measure-Object -Maximum).Maximum
    for ($i = 0; $i -lt $binding.Count; $i++) {
        $r = $binding[$i]
        $y = $top + ($i + 1) * $rowh
        $beta = [double]$r.beta_i
        $cap = [double]$r.gfm_bess_capacity_GW
        $rank = [int]$r.rank_beta
        $bw = if ($maxBeta -gt 0) { $barw * $beta / $maxBeta } else { 0 }
        $g.DrawString("$rank. $($r.region_name)", $fontSmall, $black, 10, $y - 10)
        $g.FillRectangle($blue, $left, $y - 8, [float]$bw, 10)
        $rad = if ($maxCap -gt 0) { 3 + 10 * [Math]::Sqrt($cap / $maxCap) } else { 3 }
        $g.FillEllipse($red, [float]($left + $bw + 15 - $rad), [float]($y - 3 - $rad), [float](2 * $rad), [float](2 * $rad))
        if ($r.top5_flag -eq "true") {
            $g.DrawString(("{0:N2} GW" -f $cap), $fontSmall, $black, [float]($left + $bw + 35), $y - 10)
        }
    }
    $g.DrawString("x-axis: binding frequency beta_i; marker size: installed BESS-GFM capacity", $font, $black, $left, 745)
}

$margin = Import-Csv (Join-Path $OutDir "figure_margin_data.csv")
New-Canvas (Join-Path $OutDir "figure_margin.png") 1100 650 {
    param($g)
    $g.DrawString("Post-hoc gSCR margin and local Gershgorin slack", $fontTitle, $black, 310, 18)
    $labels = @("BASE", "gSCR-GERSH")
    $left = 110; $plotTop = 70; $plotH = 450; $plotW = 360; $axisBottom = $plotTop + $plotH
    $allMargins = @($labels | ForEach-Object { $lab=$_; $margin | Where-Object {$_.scenario -eq $lab} | ForEach-Object {[double]$_.global_margin_gSCR_minus_alpha} })
    $minM = ($allMargins | Measure-Object -Minimum).Minimum
    $maxM = [Math]::Max(0.1, ($allMargins | Measure-Object -Maximum).Maximum)
    function Y1($v) { return $axisBottom - (($v - $minM) / ($maxM - $minM)) * $plotH }
    $g.DrawString("Global margin gSCR_t - alpha", $font, $black, $left + 95, 50)
    $g.DrawLine($zeroPen, $left, [float](Y1 0.0), $left + $plotW, [float](Y1 0.0))
    for ($i=0; $i -lt $labels.Count; $i++) {
        $lab = $labels[$i]
        $vals = [double[]]@($margin | Where-Object {$_.scenario -eq $lab} | ForEach-Object {[double]$_.global_margin_gSCR_minus_alpha})
        $q = Quantiles $vals
        $x = $left + 120 + 120*$i
        $g.DrawLine($pen, $x, [float](Y1 $q[0]), $x, [float](Y1 $q[4]))
        $g.FillRectangle([System.Drawing.Brushes]::LightSkyBlue, $x-28, [float](Y1 $q[3]), 56, [float]((Y1 $q[1]) - (Y1 $q[3])))
        $g.DrawRectangle($pen, $x-28, [float](Y1 $q[3]), 56, [float]((Y1 $q[1]) - (Y1 $q[3])))
        $g.DrawLine($pen, $x-28, [float](Y1 $q[2]), $x+28, [float](Y1 $q[2]))
        $g.DrawString($lab, $font, $black, $x-35, $axisBottom + 12)
    }

    $right = 620; $rplotW = 360
    $slack = [double[]]@($margin | Where-Object {$_.scenario -eq "gSCR-GERSH"} | ForEach-Object {[double]$_.min_local_kappa})
    $minS = ($slack | Measure-Object -Minimum).Minimum
    $maxS = [Math]::Max(0.1, ($slack | Measure-Object -Maximum).Maximum)
    function Y2($v) { return $axisBottom - (($v - $minS) / ($maxS - $minS)) * $plotH }
    $g.DrawString("Minimum local kappa_i,t (gSCR-GERSH)", $font, $black, $right + 70, 50)
    $g.DrawLine($zeroPen, $right, [float](Y2 0.0), $right + $rplotW, [float](Y2 0.0))
    $qs = Quantiles $slack
    $x2 = $right + 180
    $g.DrawLine($pen, $x2, [float](Y2 $qs[0]), $x2, [float](Y2 $qs[4]))
    $g.FillRectangle($gold, $x2-40, [float](Y2 $qs[3]), 80, [float]((Y2 $qs[1]) - (Y2 $qs[3])))
    $g.DrawRectangle($pen, $x2-40, [float](Y2 $qs[3]), 80, [float]((Y2 $qs[1]) - (Y2 $qs[3])))
    $g.DrawLine($pen, $x2-40, [float](Y2 $qs[2]), $x2+40, [float](Y2 $qs[2]))
    $g.DrawString("Box plots show min, quartiles, median, and max; dashed lines mark zero.", $font, $black, 250, 610)
}
