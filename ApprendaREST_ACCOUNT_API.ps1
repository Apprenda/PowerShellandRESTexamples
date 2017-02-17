$baseURI  = "https://apps.apprenda.harp/"
#$baseURI  = "https://apps.apprenda.<insert platform URL>/"
#$authJSON = '{"username":"<insert email address>","password":"<insert password>"}'
$authJSON = '{"username":"mmichael@apprenda.com","password":"password"}'
$global:ApprendaSessiontoken = [string]::Empty

function GetSessionToken($body, $authURI)
{    
    $uri = $baseURI + $authURI
    try 
    {
        $jsonOutput = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body     
        $global:ApprendaSessiontoken = $jsonOutput.apprendaSessionToken
        Write-Host "The Apprenda session token is " $global:ApprendaSessiontoken -ForegroundColor DarkYellow
    }
    catch [System.Exception]
    {
        $exceptionMessage = $_.Exception.ToString()
        Write-Error "Caught exception $exceptionMessage during execution of GetSessionToken for URI $uri. Exiting..."
        exit 23
    }  
}

function InvokeRESTMethod($body, $requestURI, $methodType)
{
    $Headers = @{}
    $Headers["ApprendaSessionToken"] = $global:ApprendaSessiontoken

    if ($requestURI -notlike "https://*")
    {
        $uri = $baseURI + $requestURI
    }
    else
    {
        $uri = $requestURI
    }

    $response = [string]::Empty
    try
    {
        if ([string]::IsNullOrEmpty($body))
        {
            $response = Invoke-WebRequest -Uri $uri -Method $methodType -ContentType "application/json" -Headers $Headers
        }
        else
        {
            $response = Invoke-WebRequest -Uri $uri -Method $methodType -ContentType "application/json" -Body $body -Headers $Headers 
        }
    
        # Apprenda REST API Response Codes: http://docs.apprenda.com/restapi/appmanagement/v1/response_codes
        if ($response.StatusCode -lt 400)
        {
            Write-Host "Method $requestURI was successful with Status Code" $response.StatusCode " and Description " $response.StatusDescription
        }
        else
        {
            Write-Error "Method $requestURI failed with Status Code" $response.StatusCode " and Description " $response.StatusDescription 
        }
        
        if (($response.Content | convertfrom-json).Messages -is [Array])
        {
            foreach ($message in ($response.Content | convertfrom-json).Messages)
            {
                if (![string]::IsNullOrEmpty($message))
                {
                    Write-Warning $message 
                }
            }
        }

        return $response
    }
    catch [System.Exception]
    {
        $exceptionMessage = $_.Exception.ToString()
        Write-Error "Caught exception $exceptionMessage during execution of URI $requestURI."
    }  
}

# Initiate an Apprenda session and get the Auth Token
GetSessionToken $authJSON "authentication/api/v1/sessions/account"

# check if the platform is undergoing an upgrade
$response = InvokeRESTMethod $null "account/api/v1/platform/upgradeStatus" "Get"
$upgradeEndpoint = $response.Content | ConvertFrom-Json
write-host "Upgrade Status is " $upgradeEndpoint.upgradeInProgress

# get all application versions
$response = InvokeRESTMethod $null "account/api/v1/applicationVersions" "Get"
$applicationVersions = $response.Content | ConvertFrom-Json
$toprint = $applicationVersions.items | select applicationAlias, applicationName, providerName
$toprint | format-table

# get all roles
$response = InvokeRESTMethod $null "account/api/v1/roles" "Get"
$roles = $response.Content | ConvertFrom-Json
$toprint = $roles.items | select name, securables
$toprint | format-table

# get the securables for the roles above
foreach ($role in $roles.items)
{
    $securablesHref = $role.securables.href
    $response = InvokeRESTMethod $null $securablesHref "Get"
    $securables = $response.Content | ConvertFrom-Json
    foreach ($securable in $securables.items)
    {
        write-host "Role $($role.name) has securable $($securable.name) enabled"
    }    
}

# get all users
$response = InvokeRESTMethod $null "account/api/v1/users" "Get"
$users = $response.Content | ConvertFrom-Json
$toprint = $users.items | select firstName, lastName, email, identifier
$toprint | format-table

foreach ($user in $users.items)
{
    # get all user roles for this user
    $response = InvokeRESTMethod $null "account/api/v1/roles?userId=$($user.identifier)" "Get"
    $userRoles = $response.Content | ConvertFrom-Json    
    foreach ($role in $userRoles.items)
    {
        write-host "User $($user.email) is a member of $($role.name)"
    }
}

# add a new user
$jsonBody = '{
  "description": "demo account",
  "email": "mmichael2@apprenda.com",
  "firstName": "Michael2",
  "lastName": "Michael2",
  "name": "Michael2 Michael2",
  "roles": {},
  "subscriptions": {}
}'
$response = InvokeRESTMethod $jsonBody "account/api/v1/users" "POST"
$user = $response.Content | ConvertFrom-Json
$toprint = $user | select firstName, lastName, email, identifier
$toprint | format-table

# add a new role
$jsonBody = '{
  "description": "TempRole1",
  "name": "Temporary Role 1",
}'
$response = InvokeRESTMethod $jsonBody "account/api/v1/roles" "POST"
$role = $response.Content | ConvertFrom-Json
$toprint = $role | select id, Description, Name
$toprint | format-table

# add the new user to a role
$jsonBody = "[""$($user.identifier)""]"
$response = InvokeRESTMethod $jsonBody $($role.users.href) "POST"

# give the role access to all of the securables
# first get all the apps
$response = InvokeRESTMethod $null "account/api/v1/applicationVersions" "Get"
$applicationVersions = $response.Content | ConvertFrom-Json
foreach ($app in $applicationVersions.items)
{
    # get all securables for this app
    $securableHref = $app.securables.href
    $response = InvokeRESTMethod $null $securableHref "Get"
    $securables= $response.Content | ConvertFrom-Json
    foreach ($securable in $securables.items)
    {
        # assign the role to each securable
        $jsonBody = "[""$($role.name)""]"
        $response = InvokeRESTMethod $jsonBody $($securable.roles.href) "POST"
    }   
}

# delete the role and user we just created
$response = InvokeRESTMethod $null $($user.href) "DELETE"
$response = InvokeRESTMethod $null $($role.href) "DELETE"
