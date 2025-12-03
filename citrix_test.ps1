$clientId = "c6b1057d-2205-45f3-b245-6e63774037ef"
$clientSecret = "GpMh5VdN1sY_8KM25n8nZA=="
$customerId = "89vz2ns4ps2m"
$catalogName = "054 - USCUST - Cyber Infrastructure - DM - vSAN - Win10x64"
$siteId = "97efb982-6793-42d0-b25d-3da94c8acb32"

$tokenUrl = "https://api.cloud.com/cctrustoauth2/root/tokens/clients"

$response = Invoke-WebRequest $tokenUrl -Method POST -Body @{
  grant_type = "client_credentials"
  client_id = $clientId
  client_secret = $clientSecret
}
 
 $token = $response.Content | ConvertFrom-Json
$token | Format-List


$headers = @{
    Authorization = "CwsAuth Bearer=$($token.access_token)"
    'Citrix-CustomerId' = $customerId
    'Citrix-InstanceId' = $siteId
    Accept = 'application/json'
}

$machinesUrl = "https://api.cloud.com/cvad/manage/Machines"
$response = Invoke-RestMethod -Uri $machinesUrl -Headers $headers
$response.Items | Select-Object Name, RegistrationState, LastConnectionBroker


$connectoruri = "https://api.cloud.com/connectors"
$respond = Invoke-RestMethod -Uri $connectoruri -Headers $headers



$catalogsUrl = "https://api.cloud.com/cvad/manage/MachineCatalogs"


# Use Invoke-RestMethod to get native objects
try {
    $catalogsResponse = Invoke-RestMethod -Uri $catalogsUrl -Method GET -Headers $headers -ErrorAction Stop
} catch {
    Write-Error "Catalogs request failed: $($_.Exception.Message)"
    return
}

# The response schema contains Items[] with catalog details
# Show name, id, provisioning type, and counts
$catalogsResponse.Items | Select-Object Name









##################################################
$response = Invoke-WebRequest "https://core.citrixworkspacesapi.net/$customerId/serviceStates" ` -Headers $headers
$serviceStates = $response | ConvertFrom-Json
$serviceStates | ConvertTo-Json -Depth 10

$serviceStates.items | Where-Object state -eq 'Production' | Select-Object -Property serviceName
##############################################

$response = Invoke-WebRequest "https://api-us.cloud.com/cvadapis/me" ` -Headers $headers
$response | ConvertFrom-Json | ConvertTo-Json -Depth 10
 
#################################

$response = Invoke-WebRequest "https://api-us.cloud.com/cvadapis/$siteId/MachineCatalogs/$catalogName/Machines" -Headers $Headers
$machines = $response | convertFrom-Json 
 
 
 
 