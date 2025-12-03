
# --- USER SETTINGS ---
$clientId = "c6b1057d-2205-45f3-b245-6e63774037ef"
$clientSecret = "GpMh5VdN1sY_8KM25n8nZA=="
$customerId = "89vz2ns4ps2m"
$siteId = "97efb982-6793-42d0-b25d-3da94c8acb32"

# --- ENDPOINTS (use region-specific base if applicable: api-us.cloud.com / api-eu.cloud.com / api-ap-s.cloud.com) ---
$apiBase           = "https://api.cloud.com"
$tokenUrl          = "$apiBase/cctrustoauth2/$customerId/tokens/clients"
$connectorsUrl     = "$apiBase/connectors"
$resLocUrl         = "$apiBase/resourcelocations"
$machineCatalogsUrl= "$apiBase/cvad/manage/MachineCatalogs"

$ErrorActionPreference = 'Stop'

function Get-BearerToken {
    param($tokenEndpoint, $clientId, $clientSecret)
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $clientId
        client_secret = $clientSecret
    }
    $resp = Invoke-WebRequest -Uri $tokenEndpoint -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
    ($resp.Content | ConvertFrom-Json).access_token
}

Write-Host "Getting token..." -ForegroundColor Cyan
$token = Get-BearerToken -tokenEndpoint $tokenUrl -clientId $clientId -clientSecret $clientSecret
if (-not $token) { throw "Token acquisition failed." }

# --- Shared headers (Cloud APIs) ---
$cloudHeaders = @{
    Authorization       = "CwsAuth Bearer=$token"
    'Citrix-CustomerId' = $customerId
    Accept              = 'application/json'
}

# --- CVAD manage headers (add InstanceId) ---
$cvadHeaders = $cloudHeaders.Clone()
$cvadHeaders['Citrix-InstanceId'] = $siteId

# 1) Connectors (each with a 'location' GUID)
Write-Host "Querying Cloud Connectors..." -ForegroundColor Cyan
$connectors = Invoke-RestMethod -Uri $connectorsUrl -Method GET -Headers $cloudHeaders
# sample fields: id, fqdn, location, status, currentVersion, versionState, lastContactDate, connectorType
# Docs: https://developer-docs.citrix.com/en-us/citrix-cloud/citrix-cloud-connectors/apis/
#      and Getting Started https://developer-docs.citrix.com/en-us/citrix-cloud/citrix-cloud-connectors/getting-started.html

# 2) Resource Locations (id -> name)
Write-Host "Querying Resource Locations..." -ForegroundColor Cyan
$resLocResp = Invoke-RestMethod -Uri $resLocUrl -Method GET -Headers $cloudHeaders
$resLocs = $resLocResp.items
# Docs: https://developer-docs.citrix.com/en-us/citrix-cloud/citrix-cloud-resource-locations/gettingstarted.html

# Build map of locationId -> locationName
$locationNameById = @{}
foreach ($rl in $resLocs) { $locationNameById[$rl.id] = $rl.name }

# Annotate connectors with ResourceLocationName
foreach ($cc in $connectors) { $cc | Add-Member -NotePropertyName ResourceLocationName -NotePropertyValue ($locationNameById[$cc.location]) }

# 3) Machine Catalogs (include Zone.Name)
Write-Host "Querying Machine Catalogs..." -ForegroundColor Cyan
$catalogsResp = Invoke-RestMethod -Uri $machineCatalogsUrl -Method GET -Headers $cvadHeaders
$catalogs = $catalogsResp.Items
# Docs: https://developer-docs.citrix.com/en-us/citrix-daas-service-apis/citrix-daas-rest-apis/how-to-get-machine-catalogs.html

# Optional: trim to essentials
$catalogsSlim = $catalogs | Select-Object `
    @{n='CatalogName';e={$_.Name}},
    @{n='CatalogId';e={$_.Id}},
    ProvisioningType,
    SessionSupport,
    AllocationType,
    @{n='ZoneName';e={ if ($_.Zone) { $_.Zone.Name } else { $null } }}

# --- Correlate: ResourceLocationName (from connectors) ↔ ZoneName (from catalogs)
# We assume ZoneName == ResourceLocationName (Citrix equates a Zone with a Resource Location)
# Docs: resource location / zone equivalence explained here: https://docs.citrix.com/en-us/citrix-daas/install-configure/resource-location.html
#       and MachineCatalogs payload includes Zone { Name }: https://developer-docs.citrix.com/en-us/citrix-daas-service-apis/citrix-daas-rest-apis/how-to-get-machine-catalogs.html

# Group connectors by Resource Location
$connectorsByRL = $connectors | Group-Object ResourceLocationName

# Build output objects: one line per catalog, listing connectors in same resource location/zone
$rows = @()
foreach ($cat in $catalogsSlim) {
    $rlName = $cat.ZoneName
    $matchingGroup = $connectorsByRL | Where-Object { $_.Name -eq $rlName }
    $connectorList = if ($matchingGroup) { ($matchingGroup.Group | Sort-Object fqdn | ForEach-Object { $_.fqdn }) -join ', ' } else { "" }

    $rows += [pscustomobject]@{
        ResourceLocation_Zone = $rlName
        CatalogName           = $cat.CatalogName
        CatalogId             = $cat.CatalogId
        ProvisioningType      = $cat.ProvisioningType
        ConnectorsInLocation  = $connectorList
    }
}

Write-Host "`n=== Connector ↔ Catalog (by Resource Location / Zone) ===" -ForegroundColor Yellow
$rows | Sort-Object ResourceLocation_Zone, CatalogName | Format-Table -Auto


# After you already built $catalogsSlim and $connectors grouped by ResourceLocationName:

$rowsExpanded = foreach ($cat in $catalogsSlim) {
    $rlName = $cat.ZoneName
    $candidateConnectors =
        $connectors |
        Where-Object { $_.ResourceLocationName -eq $rlName } |
        Sort-Object fqdn

    if ($candidateConnectors.Count -eq 0) {
        [pscustomobject]@{
            ZoneName      = $rlName
            CatalogName   = $cat.CatalogName
            CatalogId     = $cat.CatalogId
            ConnectorFqdn = "<none in location>"
            ConnectorStatus = ""
        }
    } else {
        foreach ($cc in $candidateConnectors) {
            [pscustomobject]@{
                ZoneName        = $rlName
                CatalogName     = $cat.CatalogName
                CatalogId       = $cat.CatalogId
                ConnectorFqdn   = $cc.fqdn
                ConnectorStatus = $cc.status
            }
        }
    }
}

$rowsExpanded | Format-Table -Auto


# After you query /connectors into $connectors, expand your output:
$now = Get-Date
$diagnostic = $connectors | Sort-Object ResourceLocationName, fqdn | ForEach-Object {
    $ageMin = if ($_.lastContactDate) { [math]::Round(($now - [datetime]$_.lastContactDate).TotalMinutes) } else { $null }
    [pscustomobject]@{
        ZoneName        = $_.ResourceLocationName
        ConnectorFqdn   = $_.fqdn
        ConnectorStatus = $_.status           # Unknown, Healthy, etc.
        InMaintenance   = $_.inMaintenance
        VersionState    = $_.versionState     # Normal, UpdateAvailable, etc.
        CurrentVersion  = $_.currentVersion
        ExpectedVersion = $_.expectedVersion
        LastContactDate = $_.lastContactDate
        LastContactAgeM = $ageMin
    }
}

$diagnostic | Format-Table -Auto

