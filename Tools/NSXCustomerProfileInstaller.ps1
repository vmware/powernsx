#############################
# Bootstrap script for installing customer profiling scripts and prereqs
# 
# Nick Bradford, nbradford@vmware.com


#Copyright © 2015 VMware, Inc. All Rights Reserved.

#Permission is hereby granted, free of charge, to any person obtaining a copy of
#this software and associated documentation files (the "Software"), to deal in 
#the Software without restriction, including without limitation the rights to 
#use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
#of the Software, and to permit persons to whom the Software is furnished to do 
#so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

### Note
#This powershell module should be considered entirely experimental and dangerous
#and is likely to kill babies, cause war and pestilence and permanently block all 
#your toilets.  Seriously - It's still in development,  not tested beyond lab 
#scenarios, and its recommended you dont use it for any production environment 
#without testing extensively!


$temppath = "$env:temp\VMware\VMware NSX Support Utility Installer"
$InstallPath = "$($env:ProgramData)\VMware\VMware NSX Support Utility"
$targetPNSXVersion = New-Object System.Version("2.0.0")
$repo = "https://bitbucket.org/nbradford/PowerNSX/raw/Dev"
$CuProfilingScript = "$repo/Tools/NSXCustomerProfile.ps1"
$PowerNSXInstaller = "$repo/PowerNSXInstaller.ps1"


function Download-TextFile { 

    #Stupidly simple text file downloader.
    param (

        [string]$source,
        [string]$destination
        
    )
    
    $wc = new-object Net.WebClient

    try {
        write-progress -Activity "Download $source -> $destination"
        [string]$text = $wc.DownloadString($source)
    }
    catch { 
        if ( $_.exception.innerexception -match "(407)" ) {
            $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"
            $wc.DownloadString($labModule) 
        } 
        else { 
            throw $_ 
        }
    }

    try { 
        $text | set-content $destination
    } 
    catch { 
        throw $_ 
    }
    write-progress -Activity "Download $source -> $destination" -completed
    write-host "Downloaded $destination"

}

function Check-PowerCliAsemblies {

    #Checks for known assemblies loaded by PowerCLI.
    #PowerNSX uses a variety of types, and full operation requires 
    #extensive PowerCLI usage.  
    #As of v2, we now _require_ PowerCLI assemblies to be available.
    #This method works for both PowerCLI 5.5 and 6 (snapin vs module), 
    #shouldnt be as heavy as loading each required type explicitly to check 
    #and should function in a modified PowerShell env, as well as normal 
    #PowerCLI.
    
    $RequiredAsm = (
        "VMware.VimAutomation.ViCore.Cmdlets", 
        "VMware.Vim",
        "VMware.VimAutomation.Sdk.Util10Ps",
        "VMware.VimAutomation.Sdk.Util10",
        "VMware.VimAutomation.Sdk.Interop",
        "VMware.VimAutomation.Sdk.Impl",
        "VMware.VimAutomation.Sdk.Types",
        "VMware.VimAutomation.ViCore.Types",
        "VMware.VimAutomation.ViCore.Interop",
        "VMware.VimAutomation.ViCore.Util10",
        "VMware.VimAutomation.ViCore.Util10Ps",
        "VMware.VimAutomation.ViCore.Impl",
        "VMware.VimAutomation.Vds.Commands",
        "VMware.VimAutomation.Vds.Impl",
        "VMware.VimAutomation.Vds.Interop",
        "VMware.VimAutomation.Vds.Types",
        "VMware.VimAutomation.Storage.Commands",
        "VMware.VimAutomation.Storage.Impl",
        "VMware.VimAutomation.Storage.Types",
        "VMware.VimAutomation.Storage.Interop",
        "VMware.DeployAutomation",
        "VMware.ImageBuilder"
    )


    $CurrentAsmName = foreach( $asm in ([AppDomain]::CurrentDomain.GetAssemblies())) { $asm.getName() } 
    $CurrentAsmDict = $CurrentAsmName | Group-Object -AsHashTable -Property Name

    foreach( $req in $RequiredAsm ) { 

        if ( -not $CurrentAsmDict.Contains($req) ) { 
            write-warning "PowerNSX requires PowerCLI."
            throw "Assembly $req not found.  Some required PowerCli types are not available in this PowerShell session.  Please ensure you are running the installer in a PowerCLI session, or have manually loaded the required assemblies."}
    }
}



###################################
# 

clear-host

write-host -foregroundcolor green "`n##################################################"
write-host -foregroundcolor green "Vmware Customer Profiling Tool installation script`n"
write-host -foregroundcolor green "Checking environment.`n"

#Check for Admin privs
if ( -not ( ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))) { 

    write-host -ForegroundColor Yellow "The installer requires Administrative rights."
    write-host -ForegroundColor Yellow "Please restart PowerCLI with right click, 'Run As Administrator'"
    break
}

#Check required PowerCLI assemblies are loaded.
Check-PowerCliAsemblies

if ( -not ( test-path $temppath)) { 
    write-host "Creating path $temppath"
    new-item $temppath -Type dir | out-null
}

if ( -not (test-path $InstallPath )) { 
    write-host "Creating path $InstallPath"
    New-Item -Type Directory -Path $InstallPath | out-null
}

#Check for PowerNSX
import-module powernsx -ErrorAction "ignore"
if ( -not ( Get-Module PowerNsx )  ) { 
    $version = 0
}
else { 
    $version = (Get-PowerNsxVersion).Version
}

#Upgrade / Install if required.  Temp hack to deal with the supid v1 string...
if ( -not ($version -is [System.Version] )) { 
    $UpdateRequired = $true
}
else { 
    if ( $version.CompareTo($targetPNSXVersion) -lt 0 ) {
        $UpdateRequired = $true
    }
    else {
        $UpdateRequired = $false
    }
}

while ( $UpdateRequired ) {
    $PowerNSXInstaller_filename = split-path $PowerNSXInstaller -leaf
    Download-TextFile $PowerNSXInstaller "$temppath\$PowerNSXInstaller_filename"
    $message = "PowerNSX installation or upgrade required (Current version $version, Required version $targetPNSXVersion.)"
    $question = "Perform install of PowerNSX?"
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    write-host

    if ( $decision -ne 0 ) { 
        write-host -ForegroundColor Yellow "Automated installation of PowerNSX rejected."
 
        break
    }
    else {

        invoke-expression '& "$temppath\$PowerNSXInstaller_filename"'

        if ( Get-Module PowerNsx ) { 
            remove-module PowerNsx
        }

        import-module powernsx -ErrorAction "ignore"
        if ( -not ( Get-Module PowerNsx )  ) { 
            $version = 0
        }
        else { 
            $version = (Get-PowerNsxVersion).Version
        }

        #Upgrade / Install if required.  Temp hack to deal with the supid v1 string...
        if ( -not ($version -is [System.Version] )) { 
            $UpdateRequired = $true
        }
        else { 
            if ( $version.CompareTo($targetPNSXVersion) -lt 0 ) {
                $UpdateRequired = $true
            }
            else {
                $UpdateRequired = $false
            }
        }
    }
}


#Get the profiling script.
write-host -foregroundcolor green "`nRetrieving customer profiling tool.`n"
$CuProfilingScript_filename = split-path $CuProfilingScript -leaf
Download-TextFile $CuProfilingScript "$InstallPath\$CuProfilingScript_filename"
write-host -foregroundcolor green "`nDone.`n"

