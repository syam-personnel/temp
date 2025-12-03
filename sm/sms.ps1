
# Assumes: $headers, $storefrontListUrl, $siteTestUrl, $siteTestReportUrl are defined
# (see earlier script for region gateway & auth)

# 1) Discover StoreFront servers from cloud
$sfResp = Invoke-RestMethod -Uri $storefrontListUrl -Headers $headers -Method GET
$storefronts = if ($sfResp.Items) { $sfResp.Items } else { $sfResp }

# 2) Trigger site-wide health test (JSON body required)
Write-Host "Triggering site health test..." -ForegroundColor Cyan
Invoke-RestMethod -Uri $siteTestUrl -Method POST -Headers $headers -ContentType 'application/json' -Body '{}'

# 3) Retrieve full test report
Write-Host "Getting test report..." -ForegroundColor Cyan
$report = Invoke-RestMethod -Uri $siteTestReportUrl -Method GET -Headers $headers

# 4) Correlate report items to StoreFront hosts
$rows = @()
foreach ($sf in $storefronts) {
  $hos = try { ([uri]$sf.Url).Host } catch { $null }
  $matche = @()

  foreach ($tr in $report.TestResults) {
    if ($tr.TestComponents) {
      $matche += $tr.TestComponents | Where-Object {
        $_.TestComponentTarget -and $host -and ($_.TestComponentTarget -like "*$host*")
      } | Select-Object TestComponentTarget, TestComponentStatus, ResultDetails, @{n='ParentTestName';e={$tr.TestName}}
    }
  }

  if ($matches.Count -eq 0) {
    $rows += [pscustomobject]@{
      StoreFrontName  = $sf.Name; StoreFrontUrl = $sf.Url; Enabled = $sf.Enabled
      Host            = $host;     HealthStatus  = "No component match"; Details = ""
    }
  } else {
    foreach ($m in $matches) {
      $rows += [pscustomobject]@{
        StoreFrontName  = $sf.Name; StoreFrontUrl = $sf.Url; Enabled = $sf.Enabled
        Host            = $host;     HealthStatus  = $m.TestComponentStatus
        ParentTestName  = $m.ParentTestName
        Details         = ($m.ResultDetails | ConvertTo-Json -Depth 6)
      }
    }
  }
}

$rows | Sort-Object StoreFrontName, ParentTestName, Host | Format-Table -Auto
