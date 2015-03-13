$baseURI  = "https://apps.apprenda.harp/"
$authJSON = '{"username":"<Insert Apprenda Email Address for this User>","password":"<Insert Password>"}'
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

    $uri = $baseURI + $requestURI
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
GetSessionToken $authJSON "authentication/api/v1/sessions/developer"

# Get a list of all the applications you are authorized to view
$response = InvokeRESTMethod $null "developer/api/v1/apps" "Get"
write-host "Printing all the apps I am authorized to view based on my tenant" 
write-host "-->"
if ($response.Content.Length -gt 0)
{
    foreach ($item in  ($response.Content | convertfrom-json))
    {
        Write-Host $item.Name "`t" $item.href -ForegroundColor Yellow
    }
}
write-host "<--"

# Create a new application in Apprenda
$applicationUniqueName = "TimeCard"
$newAppJSON = "{""Name"":""$applicationUniqueName"",""Alias"":""$applicationUniqueName"",""Description"":""An app created from PowerShell over REST""}"
$response = InvokeRESTMethod $newAppJSON "developer/api/v1/apps" "POST"

# Upload an archive for the application I created above
$archiveURL = "http://docs.apprenda.com/sites/default/files/TimeCard.zip"
$response = InvokeRESTMethod "" "developer/api/v1/versions/$applicationUniqueName/v1?action=setArchive&archiveUri=$archiveURL" "POST"



