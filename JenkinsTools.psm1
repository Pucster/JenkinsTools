<#
Module: JenkinsTools
Author: Derek Ardolf

NOTE: Please check out GitHub for latest revisions
Link: https://github.com/ScriptAutomate/JenkinsTools
#>

function New-JenkyCredential {
<#
	.SYNOPSIS
		Creates an encrypted dump of credentials for use by the JenkinsTools Module agains the Jenkins Remote API.

	.DESCRIPTION
		Using credentials securely dumped by New-JTCredential, JenkinsTools Module functions interact with the Jenkins Remote API. Credentials are encrypted using DPAPI -- see link at end of help documentation.

	.PARAMETER  Credential
		Credentials for accessing the Jenkins Remote API. The credential should be created with the 'User ID' and 'API Token' listed for your account. To find these:
    - Logon to your account in Jenkins
    - At the top-right side of the page, click the drop-down menu next to your name and select 'Configure'
    - On the 'Configure' page, you with see an 'API Token' section where you can click a button saying 'Show API Token.' This button will reveal both the 'User ID' and 'API Token' values necessary for accessing the Jenkins Remote API.

	.PARAMETER  Force
		Will overwrite any previously generated credentials.
    
  .PARAMETER  Url
    The Url of the Jenkins server that the credentials are being created to access. Example: http://jenkins.contoso.com

  .INPUTS
    System.Management.Automation.PSCredential

  .OUTPUTS
    None

	.EXAMPLE
		PS C:\> New-JTCredential -Url http://jenkins.contoso.com -Credential $Credential
      
      Uses the credentials stored in the $Credential variable to dump to module's root path, after testing authentication against http://jenkins.contoso.com.

	.EXAMPLE
		PS C:\> $Credential | New-JTCredential -Url http://jenkins.contoso.com -Force
    
      Uses the credentials stored in the $Credential variable to dump to module's root path, after testing authentication against http://jenkins.contoso.com. The -Force parameter overwrites pre-existing credentials.

	.LINK
		https://github.com/ScriptAutomate/JenkinsTools
  .LINK
		https://halfwaytoinfinite.wordpress.com
  .LINK
    https://wiki.jenkins-ci.org/display/JENKINS/Remote+access+API
  .LINK
    https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
  .LINK
		http://msdn.microsoft.com/en-us/library/ms995355.aspx
  .LINK
    http://powershell.org/wp/2013/11/24/saving-passwords-and-preventing-other-processes-from-decrypting-them/comment-page-1/
  
  .COMPONENT
    Invoke-RestMethod
    Get-Credential
    ConvertTo-SecureString
    ConvertFrom-SecureString
    
#>
[CmdletBinding()]
Param
(
  [Parameter(Mandatory=$True)]
  [Alias("JenkinsUrl")]
  [String]$Url,
  [Parameter(Mandatory=$False,ValueFromPipeline=$True)]
  [System.Management.Automation.PSCredential]$Credential,
  [Parameter(Mandatory=$False)]
  [Switch]$Force 
)
  $ModuleLocation = (Get-Module JenkinsTools).Path.Replace('\JenkinsTools.psm1','')
  if (Test-Path "$ModuleLocation\JenkyAuth1") {
    if (!$Force) {
      Write-Error "$ModuleLocation\JenkyAuth* credentials already exist. Use with -Force parameter to overwrite."
      break
    }
    else { 
      Write-Warning "$ModuleLocation\JenkyAuth* credentials already exist. -Force parameter was used -- overwriting..."
    }
  }
  
  try {
    if (!$Credential) {
      $Credential = Get-Credential -Message "Enter Credentials to Query the Jenkins Remote API"
      if (!$Credential) {break}
    }
    
    Write-Warning "Verifying credentials..."
    $JenkinsBaseAPI = $Url
    $null = Invoke-RestMethod $JenkinsBaseAPI -Credential $Credential
    
    # If credentials worked, export secure string text
    $Credential.GetNetworkCredential().Password | 
      ConvertTo-SecureString -AsPlainText -Force | 
      ConvertFrom-SecureString | 
      Out-File "$ModuleLocation\JenkyAuth1"
    $Credential.UserName | 
      ConvertTo-SecureString -AsPlainText -Force | 
      ConvertFrom-SecureString | 
      Out-File "$ModuleLocation\JenkyAuth2"
    $Url |
      ConvertTo-SecureString -AsPlainText -Force |
      ConvertFrom-SecureString |
      Out-File "$ModuleLocation\JenkyAuth3"
      
    Write-Warning "Credentials successfully tested, and exported." 
    Write-Warning "All commands from the JenkinsTools Module will now use these credentials."
  }
  catch {
    Write-Error $_.Exception
    break
  }
}

function Get-JenkyJob {
[CmdletBinding()]
Param
(
  [Parameter(Mandatory=$false)]
  [String[]]$Name,
  [Parameter(Mandatory=$false)]
  [Alias("JenkinsUrlBase")]
  [String]$Url,
  [Parameter(Mandatory=$False)]
  [System.Management.Automation.PSCredential]$Credential
)
  Begin {
    # Checking for credentials
    $ModuleLocation = (Get-Module JenkinsTools).Path.Replace('\JenkinsTools.psm1','')
    $JenkyPass = "$ModuleLocation\JenkyAuth1"
    $JenkyUser = "$ModuleLocation\JenkyAuth2"
    $JenkyUrl = "$ModuleLocation\JenkyAuth3"
    if (!$Credential) {
      if ((Test-Path "$JenkyPass") -and (Test-Path "$JenkyUser")) {
        $CredUserSecure = Get-Content "$JenkyUser" | ConvertTo-SecureString
        $BSTRUser = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredUserSecure)
        $CredUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUser)
        $CredPassSecure = Get-Content "$JenkyPass" | ConvertTo-SecureString
        $BSTRPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredPassSecure)
        $CredPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRPass)        
        $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$CredUser" + ":" + "$CredPass")))"}
      }
      else {
        Write-Error "Failure to find credentials. You must run New-JTCredential before you can use the JenkinsTools Module."
        break
      }
    }
    else {
      $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Credential.UserName" + ":" + "$Credential.GetNetworkCredential().Password")))"}
    }
    if (!$Url) {
      if (Test-Path "$JenkyUrl") {
        $CredSecureUrl = Get-Content "$JenkyUrl" | ConvertTo-SecureString
        $BSTRUrl = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredSecureUrl)
        $JenkyBaseAPI = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUrl)
      }
    }
    else {$JenkyBaseAPI = "$Url"}
  }
  
  Process {
    $JenkyFullAPI = "$JenkyBaseAPI/api/json?tree=jobs[name,url]"
    $Retrieve = (Invoke-RestMethod "$JenkyFullAPI").Jobs
    if ($Name) {
      foreach ($Query in $Name) {
        $Jobs += $Retrieve | where {$_.Name -like "$Query"}
      }
      $Jobs
    }
    else {$Retrieve}
  }
}

function Get-JenkyView {
[CmdletBinding()]
Param
(
  [Parameter(Mandatory=$false)]
  [String[]]$Name,
  [Parameter(Mandatory=$false)]
  [Alias("JenkinsUrlBase")]
  [String]$Url,
  [Parameter(Mandatory=$False)]
  [System.Management.Automation.PSCredential]$Credential
)
  Begin {
    # Checking for credentials
    $ModuleLocation = (Get-Module JenkinsTools).Path.Replace('\JenkinsTools.psm1','')
    $JenkyPass = "$ModuleLocation\JenkyAuth1"
    $JenkyUser = "$ModuleLocation\JenkyAuth2"
    $JenkyUrl = "$ModuleLocation\JenkyAuth3"
    if (!$Credential) {
      if ((Test-Path "$JenkyPass") -and (Test-Path "$JenkyUser")) {
        $CredUserSecure = Get-Content "$JenkyUser" | ConvertTo-SecureString
        $BSTRUser = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredUserSecure)
        $CredUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUser)
        $CredPassSecure = Get-Content "$JenkyPass" | ConvertTo-SecureString
        $BSTRPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredPassSecure)
        $CredPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRPass)        
        $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$CredUser" + ":" + "$CredPass")))"}
      }
      else {
        Write-Error "Failure to find credentials. You must run New-JTCredential before you can use the JenkinsTools Module."
        break
      }
    }
    else {
      $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Credential.UserName" + ":" + "$Credential.GetNetworkCredential().Password")))"}
    }
    if (!$Url) {
      if (Test-Path "$JenkyUrl") {
        $CredSecureUrl = Get-Content "$JenkyUrl" | ConvertTo-SecureString
        $BSTRUrl = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredSecureUrl)
        $JenkyBaseAPI = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUrl)
      }
    }
    else {$JenkyBaseAPI = "$Url"}
  }
  
  Process {
    $JenkyFullAPI = "$JenkyBaseAPI/api/json?tree=views[name,jobs[name,url]]"
    $Retrieve = (Invoke-RestMethod "$JenkyFullAPI").Views | select Name,Jobs
    if ($Name) {
      foreach ($Query in $Name) {
        $Retrieve | where {$_.Name -like "$Query"}
      }
    }
    else {$Retrieve}
  }
}

function Get-JenkyService {
[CmdletBinding()]
Param
(
  [Parameter(Mandatory=$false)]
  [String[]]$Name,
  [Parameter(Mandatory=$false)]
  [Alias("JenkinsUrlBase")]
  [String]$Url,
  [Parameter(Mandatory=$False)]
  [System.Management.Automation.PSCredential]$Credential
)
  Begin {
    # Checking for credentials
    $ModuleLocation = (Get-Module JenkinsTools).Path.Replace('\JenkinsTools.psm1','')
    $JenkyPass = "$ModuleLocation\JenkyAuth1"
    $JenkyUser = "$ModuleLocation\JenkyAuth2"
    $JenkyUrl = "$ModuleLocation\JenkyAuth3"
    if (!$Credential) {
      if ((Test-Path "$JenkyPass") -and (Test-Path "$JenkyUser")) {
        $CredUserSecure = Get-Content "$JenkyUser" | ConvertTo-SecureString
        $BSTRUser = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredUserSecure)
        $CredUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUser)
        $CredPassSecure = Get-Content "$JenkyPass" | ConvertTo-SecureString
        $BSTRPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredPassSecure)
        $CredPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRPass)        
        $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$CredUser" + ":" + "$CredPass")))"}
      }
      else {
        Write-Error "Failure to find credentials. You must run New-JTCredential before you can use the JenkinsTools Module."
        break
      }
    }
    else {
      $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Credential.UserName" + ":" + "$Credential.GetNetworkCredential().Password")))"}
    }
    if (!$Url) {
      if (Test-Path "$JenkyUrl") {
        $CredSecureUrl = Get-Content "$JenkyUrl" | ConvertTo-SecureString
        $BSTRUrl = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredSecureUrl)
        $JenkyBaseAPI = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUrl)
      }
    }
    else {$JenkyBaseAPI = "$Url"}
  }
  
  Process {
    $Retrieve = Invoke-WebRequest $JenkyBaseAPI
    $Hash = @{'JenkinsVersion'=($Retrieve.Headers.GetEnumerator() | where {$_.Key -eq "X-Jenkins"}).Value
              'Url'="$JenkyBaseAPI"}
    New-Object -TypeName PSObject -Property $Hash
  }
}

#function Get-JenkyQueue {
#[CmdletBinding()]
#Param
#(
#  [Parameter(Mandatory=$false)]
#  [String[]]$Name,
#  [Parameter(Mandatory=$false)]
#  [Alias("JenkinsUrlBase")]
#  [String]$Url,
#  [Parameter(Mandatory=$False)]
#  [System.Management.Automation.PSCredential]$Credential
#)
#  Begin {
#     Checking for credentials
#    $ModuleLocation = (Get-Module JenkinsTools).Path.Replace('\JenkinsTools.psm1','')
#    $JenkyPass = "$ModuleLocation\JenkyAuth1"
#    $JenkyUser = "$ModuleLocation\JenkyAuth2"
#    $JenkyUrl = "$ModuleLocation\JenkyAuth3"
#    if (!$Credential) {
#      if ((Test-Path "$JenkyPass") -and (Test-Path "$JenkyUser")) {
#        $CredUserSecure = Get-Content "$JenkyUser" | ConvertTo-SecureString
#        $BSTRUser = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredUserSecure)
#        $CredUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUser)
#        $CredPassSecure = Get-Content "$JenkyPass" | ConvertTo-SecureString
#        $BSTRPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredPassSecure)
#        $CredPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRPass)        
#        $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$CredUser" + ":" + "$CredPass")))"}
#      }
#      else {
#        Write-Error "Failure to find credentials. You must run New-JTCredential before you can use the JenkinsTools Module."
#        break
#      }
#    }
#    else {
#      $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Credential.UserName" + ":" + "$Credential.GetNetworkCredential().Password")))"}
#    }
#    if (!$Url) {
#      if (Test-Path "$JenkyUrl") {
#        $CredSecureUrl = Get-Content "$JenkyUrl" | ConvertTo-SecureString
#        $BSTRUrl = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredSecureUrl)
#        $JenkyBaseAPI = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUrl)
#      }
#    }
#    else {$JenkyBaseAPI = "$Url"}
#  }
#  
#  Process {
#    $JenkyFullAPI = "$JenkyBaseAPI/queue/api/json?"
#    (Invoke-RestMethod $JenkyFullAPI).Items
#  }
#}

function Export-JenkyJobConfiguration {
[CmdletBinding()]
Param
(
  [Parameter(Mandatory=$true)]
  $Path,
  [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
  [Alias("JenkinsJobUrl")]
  [Uri]$Url,
  [Parameter(Mandatory=$False)]
  [System.Management.Automation.PSCredential]$Credential
)
  Begin {
    # Checking for credentials
    $ModuleLocation = (Get-Module JenkinsTools).Path.Replace('\JenkinsTools.psm1','')
    $JenkyPass = "$ModuleLocation\JenkyAuth1"
    $JenkyUser = "$ModuleLocation\JenkyAuth2"
    $JenkyUrl = "$ModuleLocation\JenkyAuth3"
    if (!$Credential) {
      if ((Test-Path "$JenkyPass") -and (Test-Path "$JenkyUser")) {
        $CredUserSecure = Get-Content "$JenkyUser" | ConvertTo-SecureString
        $BSTRUser = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredUserSecure)
        $CredUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRUser)
        $CredPassSecure = Get-Content "$JenkyPass" | ConvertTo-SecureString
        $BSTRPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CredPassSecure)
        $CredPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRPass)        
        $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$CredUser" + ":" + "$CredPass")))"}
      }
      else {
        Write-Error "Failure to find credentials. You must run New-JTCredential before you can use the JenkinsTools Module."
        break
      }
    }
    else {
      $BSTRPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
      $CredPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRPass) 
      $AuthHash = @{'Authorization'="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($Credential.UserName)" + ":" + "$CredPass")))"}
    }
  }
  
  Process {
    (Invoke-WebRequest "$($Url)config.xml" -Headers $AuthHash).Content | Out-File -FilePath $Path -Encoding UTF8
  }
}

#function Import-JenkyJobConfiguration {}
#function Copy-JenkyJob {}
#function New-JenkyJob {}
#function Get-JenkyLoadStats {}
#function Restart-JenkyService {}