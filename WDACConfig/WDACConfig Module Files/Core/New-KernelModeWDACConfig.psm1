Function New-KernelModeWDACConfig {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        PositionalBinding = $false,
        ConfirmImpact = 'High'
    )]
    Param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Default Strict Kernel')][System.Management.Automation.SwitchParameter]$Default,
        [Parameter(Mandatory = $false, ParameterSetName = 'No Flight Roots')][System.Management.Automation.SwitchParameter]$NoFlightRoots,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default Strict Kernel')]
        [Parameter(Mandatory = $false, ParameterSetName = 'No Flight Roots')]
        [System.Management.Automation.SwitchParameter]$PrepMode,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default Strict Kernel')]
        [Parameter(Mandatory = $false, ParameterSetName = 'No Flight Roots')]
        [System.Management.Automation.SwitchParameter]$AuditAndEnforce,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default Strict Kernel')]
        [Parameter(Mandatory = $false, ParameterSetName = 'No Flight Roots')]
        [System.Management.Automation.SwitchParameter]$Deploy,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default Strict Kernel')]
        [Parameter(Mandatory = $false, ParameterSetName = 'No Flight Roots')]
        [System.Management.Automation.SwitchParameter]$EVSigners,

        [Parameter(Mandatory = $false)][System.Management.Automation.SwitchParameter]$SkipVersionCheck
    )

    begin {
        # Detecting if Verbose switch is used
        $PSBoundParameters.Verbose.IsPresent ? ([System.Boolean]$Verbose = $true) : ([System.Boolean]$Verbose = $false) | Out-Null

        # Importing the $PSDefaultParameterValues to the current session, prior to everything else
        . "$ModuleRootPath\CoreExt\PSDefaultParameterValues.ps1"

        # Importing the required sub-modules
        Write-Verbose -Message 'Importing the required sub-modules'
        Import-Module -FullyQualifiedName "$ModuleRootPath\Shared\Update-self.psm1" -Force
        Import-Module -FullyQualifiedName "$ModuleRootPath\Shared\Write-ColorfulText.psm1" -Force
        Import-Module -FullyQualifiedName "$ModuleRootPath\Shared\Move-UserModeToKernelMode.psm1" -Force

        # Detecting if Debug switch is used, will do debugging actions based on that
        $PSBoundParameters.Debug.IsPresent ? ([System.Boolean]$Debug = $true) : ([System.Boolean]$Debug = $false) | Out-Null

        # if -SkipVersionCheck wasn't passed, run the updater
        if (-NOT $SkipVersionCheck) { Update-self -InvocationStatement $MyInvocation.Statement }

        # Check if the PrepMode and AuditAndEnforce parameters are used together and ensure one of them is used
        if (-not ($PSBoundParameters.ContainsKey('PrepMode') -xor $PSBoundParameters.ContainsKey('AuditAndEnforce'))) {
            # Write an error message
            Write-Error -Message 'You must specify either -PrepMode or -AuditAndEnforce, but not both.' -Category InvalidArgument
        }

        Function Edit-GUIDs {
            <#
            .SYNOPSIS
                A helper function to swap GUIDs in a WDAC policy XML file
            .INPUTS
                System.String
            .OUTPUTS
                System.Void
            #>
            [CmdletBinding()]
            param(
                [System.String]$PolicyIDInput,
                [System.String]$PolicyFilePathInput
            )

            [System.String]$PolicyID = "{$PolicyIDInput}"

            # Read the xml file as an xml object
            [System.Xml.XmlDocument]$Xml = Get-Content -Path $PolicyFilePathInput

            # Define the new values for PolicyID and BasePolicyID
            [System.String]$newPolicyID = $PolicyID
            [System.String]$newBasePolicyID = $PolicyID

            # Replace the old values with the new ones
            $Xml.SiPolicy.PolicyID = $newPolicyID
            $Xml.SiPolicy.BasePolicyID = $newBasePolicyID

            # Save the modified xml file
            $Xml.Save($PolicyFilePathInput)
        }

        Function Build-PrepModeStrictKernelPolicy {
            <#
            .SYNOPSIS
                A helper function to build Audit mode policy only
            .INPUTS
                System.Management.Automation.SwitchParameter
            #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $false)][System.Management.Automation.SwitchParameter]$DefaultWindowsKernel,
                [Parameter(Mandatory = $false)][System.Management.Automation.SwitchParameter]$DefaultWindowsKernelNoFlights
            )
            begin {

                Write-Verbose -Message 'Executing the Build-PrepModeStrictKernelPolicy helper function'

                if ($DefaultWindowsKernel) {
                    [System.String]$PolicyPath = "$ModuleRootPath\Resources\WDAC Policies\DefaultWindows_Enforced_Kernel.xml"
                    [System.String]$PolicyFileName = '.\DefaultWindows_Enforced_Kernel.xml'
                    [System.String]$PolicyName = 'Strict Kernel mode policy Audit'

                    # Check if there is a pending Audit mode Kernel mode WDAC policy already available in User Config file
                    [System.String]$CurrentStrictKernelPolicyGUID = Get-CommonWDACConfig -StrictKernelPolicyGUID

                    If ($CurrentStrictKernelPolicyGUID) {
                        # Check if the pending Audit mode Kernel mode WDAC policy is deployed on the system
                        [System.String]$CurrentStrictKernelPolicyGUIDConfirmation = ((&'C:\Windows\System32\CiTool.exe' -lp -json | ConvertFrom-Json).Policies | Where-Object -FilterScript { $_.PolicyID -eq $CurrentStrictKernelPolicyGUID }).policyID
                    }
                }

                if ($DefaultWindowsKernelNoFlights) {
                    [System.String]$PolicyPath = "$ModuleRootPath\Resources\WDAC Policies\DefaultWindows_Enforced_Kernel_NoFlights.xml"
                    [System.String]$PolicyFileName = '.\DefaultWindows_Enforced_Kernel_NoFlights.xml'
                    [System.String]$PolicyName = 'Strict Kernel No Flights mode policy Audit'

                    # Check if there is a pending Audit mode Kernel mode WDAC No Flight Roots policy already available in User Config file
                    [System.String]$CurrentStrictKernelNoFlightRootsPolicyGUID = Get-CommonWDACConfig -StrictKernelNoFlightRootsPolicyGUID

                    If ($CurrentStrictKernelNoFlightRootsPolicyGUID) {
                        # Check if the pending Audit mode Kernel mode WDAC No Flight Roots policy is deployed on the system
                        [System.String]$CurrentStrictKernelPolicyGUIDConfirmation = ((&'C:\Windows\System32\CiTool.exe' -lp -json | ConvertFrom-Json).Policies | Where-Object -FilterScript { $_.PolicyID -eq $CurrentStrictKernelNoFlightRootsPolicyGUID }).policyID
                    }
                }

            }

            process {
                Write-Verbose -Message 'Copying the base policy to the current working directory'
                Copy-Item -Path $PolicyPath -Destination "$PolicyFileName" -Force
                
                # Setting them to global so they can be accessed outside of this function's scope too
                Write-Verbose -Message 'Resetting the policy ID and assigning a name for the policy'
                $Global:PolicyID = Set-CIPolicyIdInfo -FilePath "$PolicyFileName" -PolicyName "$PolicyName" -ResetPolicyID
                $Global:PolicyID = $PolicyID.Substring(11)
                
                Write-Verbose -Message 'Setting the policy version to 1.0.0.0'
                Set-CIPolicyVersion -FilePath "$PolicyFileName" -Version '1.0.0.0'
                
                Write-Verbose -Message 'Setting policy rule options for the audit mode policy'
                @(2, 3, 6, 16, 17, 20) | ForEach-Object -Process { Set-RuleOption -FilePath "$PolicyFileName" -Option $_ }
                @(0, 4, 8, 9, 10, 11, 12, 13, 14, 15, 18, 19) | ForEach-Object -Process { Set-RuleOption -FilePath "$PolicyFileName" -Option $_ -Delete }
                
                # If user chooses to add EVSigners, add it to the policy
                if ($EVSigners) {
                    Write-Verbose -Message 'Adding EVSigners policy rule option'
                    Set-RuleOption -FilePath "$PolicyFileName" -Option 8 
                }
                
                # If user chooses to go with no flight root certs then block flight/insider builds in policy rule options
                if ($DefaultWindowsKernelNoFlights) {
                    Write-Verbose -Message 'Adding policy rule option 4 to block flight root certificates'
                    Set-RuleOption -FilePath "$PolicyFileName" -Option 4 
                }

                # Set the already available and deployed GUID as the new PolicyID to prevent deploying duplicate Audit mode policies
                if ($CurrentStrictKernelPolicyGUIDConfirmation) {
                    Edit-GUIDs -PolicyIDInput $CurrentStrictKernelPolicyGUIDConfirmation -PolicyFilePathInput "$PolicyFileName"
                    $Global:PolicyID = $CurrentStrictKernelPolicyGUIDConfirmation
                }

                Write-Verbose -Message 'Setting the HVCI to Strict'
                Set-HVCIOptions -Strict -FilePath "$PolicyFileName"
            }
        }
    }

    process {

        if ($PSCmdlet.ParameterSetName -eq 'Default Strict Kernel' -and $PSBoundParameters.ContainsKey('Default')) {

            if ($PrepMode) {

                Write-Verbose -Message 'Building the Audit mode policy by calling the Build-PrepModeStrictKernelPolicy function'
                Build-PrepModeStrictKernelPolicy -DefaultWindowsKernel

                Write-Verbose -Message 'Converting the XML policy file to CIP binary'
                ConvertFrom-CIPolicy -XmlFilePath .\DefaultWindows_Enforced_Kernel.xml -BinaryFilePath "$PolicyID.cip" | Out-Null

                # Deploy the policy if Deploy parameter is used and perform additional tasks on the system
                if ($Deploy) {
                    
                    Write-Verbose -Message 'Setting the GUID of the Audit mode policy in the User Configuration file'
                    Set-CommonWDACConfig -StrictKernelPolicyGUID $PolicyID | Out-Null
                    
                    Write-Verbose -Message 'Deploying the Strict Kernel mode policy'
                    &'C:\Windows\System32\CiTool.exe' --update-policy "$PolicyID.cip" -json | Out-Null
                    Write-ColorfulText -Color HotPink -InputText 'Strict Kernel mode policy has been deployed in Audit mode, please restart your system.'

                    Write-Verbose -Message 'Clearing the Code Integrity operational event logs before system restart so that after reboot it will only have the correct and new logs that belong to the kernel mode drivers'
                    &'C:\Windows\System32\wevtutil.exe' cl 'Microsoft-Windows-CodeIntegrity/Operational'
                    &'C:\Windows\System32\wevtutil.exe' cl 'Microsoft-Windows-AppLocker/MSI and Script'

                    if (!$Debug) {
                        Write-Verbose -Message 'Removing the DefaultWindows_Enforced_Kernel.xml and its CIP file after deployment since -Debug parameter was not used.'
                        Remove-Item -Path '.\DefaultWindows_Enforced_Kernel.xml', ".\$PolicyID.cip" -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    Write-ColorfulText -Color HotPink -InputText 'Strict Kernel mode Audit policy has been created in the current working directory.'
                }
            }

            if ($AuditAndEnforce) {

                # Get the Strict Kernel Audit mode policy's GUID to use for the Enforced mode policy
                # This will eliminate the need for an extra reboot
                Write-Verbose -Message 'Trying to get the GUID of Strict Kernel Audit mode policy to use for the Enforced mode policy, from the user configurations'
                [System.String]$PolicyID = Get-CommonWDACConfig -StrictKernelPolicyGUID
                
                Write-Verbose -Message 'Verifying the Policy ID in the User Config exists and is valid'
                $ObjectGuid = [System.Guid]::Empty
                if ([System.Guid]::TryParse($PolicyID, [ref]$ObjectGuid)) {
                    Write-Verbose -Message 'Valid GUID found in User Configs for Audit mode policy'
                }
                else {
                    Throw 'Invalid or nonexistent GUID in User Configs for Audit mode policy, Use the -PrepMode parameter first.'
                }

                powershell.exe -Command {
                    Write-Verbose -Message 'Scanning the Event viewer logs for drivers'
                    $DriverFilesObj = Get-SystemDriver -Audit

                    Write-Verbose -Message 'Creating a policy xml file from the driver files'
                    New-CIPolicy -MultiplePolicyFormat -Level FilePublisher -Fallback None -FilePath '.\DriverFilesScanPolicy.xml' -DriverFiles $DriverFilesObj
                }

                Write-Verbose -Message 'Not trusting the policy xml file made before restart, so building the same policy again after restart, this time in Enforced mode instead of Audit mode'
                Copy-Item -Path "$ModuleRootPath\Resources\WDAC Policies\DefaultWindows_Enforced_Kernel.xml" -Destination .\DefaultWindows_Enforced_Kernel.xml -Force

                Write-Verbose -Message 'Merging the base policy with the policy made from driver files, to deploy them as one policy'
                Merge-CIPolicy -PolicyPaths '.\DefaultWindows_Enforced_Kernel.xml', '.\DriverFilesScanPolicy.xml' -OutputFilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' | Out-Null

                Write-Verbose -Message 'Removing the old policy again because we used it in merge and do not need it anymore'
                Remove-Item -Path '.\DefaultWindows_Enforced_Kernel.xml' -Force

                Write-Verbose -Message 'Moving all AllowedSigners from Usermode to Kernel mode signing scenario'
                Move-UserModeToKernelMode -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' | Out-Null

                Write-Verbose -Message 'Setting the GUIDs for the XML policy file'
                Edit-GUIDs -PolicyIDInput $PolicyID -PolicyFilePathInput '.\Final_DefaultWindows_Enforced_Kernel.xml'

                Write-Verbose -Message 'Setting a new policy name with the current date attached to it'
                Set-CIPolicyIdInfo -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -PolicyName "Strict Kernel mode policy Enforced - $(Get-Date -Format 'MM-dd-yyyy')"

                Write-Verbose -Message 'Setting the policy version to 1.0.0.0'
                Set-CIPolicyVersion -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Version '1.0.0.0'
                
                Write-Verbose -Message 'Setting policy rule options for the final Enforced mode policy'
                @(2, 6, 16, 17, 20) | ForEach-Object -Process { Set-RuleOption -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Option $_ }
                @(0, 3, 4, 8, 9, 10, 11, 12, 13, 14, 15, 18, 19) | ForEach-Object -Process { Set-RuleOption -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Option $_ -Delete }

                if ($EVSigners) {
                    Write-Verbose -Message 'Adding EVSigners policy rule option'
                    Set-RuleOption -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Option 8
                }

                Write-Verbose -Message 'Setting the HVCI to Strict'
                Set-HVCIOptions -Strict -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml'

                # Deploy the policy if Deploy parameter is used
                if ($Deploy) {
                    Write-Verbose -Message 'Converting the policy XML file to CIP binary'
                    ConvertFrom-CIPolicy -XmlFilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -BinaryFilePath "$PolicyID.cip" | Out-Null
                    
                    Write-Verbose -Message 'Deploying the enforced mode policy with the same ID as the Audit mode policy, effectively overwriting it'
                    &'C:\Windows\System32\CiTool.exe' --update-policy "$PolicyID.cip" -json | Out-Null
                    Write-ColorfulText -Color Pink -InputText 'Strict Kernel mode policy has been deployed in Enforced mode, no restart required.'

                    Write-Verbose -Message 'Removing the GUID of the StrictKernelPolicy from user configuration'
                    Remove-CommonWDACConfig -StrictKernelPolicyGUID | Out-Null
                }
                else {
                    # Remove the Audit mode policy from the system
                    # This step is necessary if user didn't use the -Deploy parameter
                    # And instead wants to first Sign and then deploy it using the Deploy-SignedWDACConfig cmdlet
                    Write-Verbose -Message 'Removing the deployed Audit mode policy from the system since -Deploy parameter was not used to overwrite it with the enforced mode policy.'
                    &'C:\Windows\System32\CiTool.exe' --remove-policy "{$PolicyID}" -json | Out-Null
                    Write-ColorfulText -Color Pink -InputText 'Strict Kernel mode Enforced policy has been created in the current working directory.'
                }
                if (!$Debug) {
                    Write-Verbose -Message 'Removing the DriverFilesScanPolicy.xml and the CIP file because -Debug parameter was not used'
                    Remove-Item -Path ".\$PolicyID.cip", '.\DriverFilesScanPolicy.xml' -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # For Strict Kernel mode WDAC policy without allowing Flight root certs (i.e. not allowing insider builds)
        if ($PSCmdlet.ParameterSetName -eq 'No Flight Roots' -and $PSBoundParameters.ContainsKey('NoFlightRoots')) {

            if ($PrepMode) {
                Write-Verbose -Message 'Building the Audit mode policy by calling the Build-PrepModeStrictKernelPolicy function'
                Build-PrepModeStrictKernelPolicy -DefaultWindowsKernelNoFlights
                
                Write-Verbose -Message 'Converting the XML policy file to CIP binary'
                ConvertFrom-CIPolicy -XmlFilePath .\DefaultWindows_Enforced_Kernel_NoFlights.xml -BinaryFilePath "$PolicyID.cip" | Out-Null

                # Deploy the policy if Deploy parameter is used and perform additional tasks on the system
                if ($Deploy) {

                    Write-Verbose -Message 'Setting the GUID of the Audit mode policy in the User Configuration file'
                    Set-CommonWDACConfig -StrictKernelNoFlightRootsPolicyGUID $PolicyID | Out-Null
                   
                    Write-Verbose -Message 'Deploying the Strict Kernel mode policy'
                    &'C:\Windows\System32\CiTool.exe' --update-policy "$PolicyID.cip" -json | Out-Null
                    Write-ColorfulText -Color HotPink -InputText 'Strict Kernel mode policy with no flighting root certs has been deployed in Audit mode, please restart your system.'

                    Write-Verbose -Message 'Clearing the Code Integrity operational event logs before system restart so that after reboot it will only have the correct and new logs that belong to the kernel mode drivers'
                    &'C:\Windows\System32\wevtutil.exe' cl 'Microsoft-Windows-CodeIntegrity/Operational'
                    &'C:\Windows\System32\wevtutil.exe' cl 'Microsoft-Windows-AppLocker/MSI and Script'

                    if (!$Debug) {
                        Write-Verbose -Message 'Removing the DefaultWindows_Enforced_Kernel_NoFlights.xml and its CIP file after deployment since -Debug parameter was not used.'
                        Remove-Item -Path '.\DefaultWindows_Enforced_Kernel_NoFlights.xml', ".\$PolicyID.cip" -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    Write-ColorfulText -Color HotPink -InputText 'Strict Kernel mode Audit policy with no flighting root certs has been created in the current working directory.'
                }
            }

            if ($AuditAndEnforce) {

                # Get the Strict Kernel Audit mode policy's GUID to use for the Enforced mode policy
                # This will eliminate the need for an extra reboot
                Write-Verbose -Message 'Trying to get the GUID of Strict Kernel Audit mode policy to use for the Enforced mode policy, from the user configurations'
                [System.String]$PolicyID = Get-CommonWDACConfig -StrictKernelNoFlightRootsPolicyGUID

                Write-Verbose -Message 'Verifying the Policy ID in the User Config exists and is valid'
                $ObjectGuid = [System.Guid]::Empty
                if ([System.Guid]::TryParse($PolicyID, [ref]$ObjectGuid)) {
                    Write-Verbose -Message 'Valid GUID found in User Configs for Audit mode policy'
                }
                else {
                    Throw 'Invalid or nonexistent GUID in User Configs for Audit mode policy, Use the -PrepMode parameter first.'
                }

                powershell.exe -Command {
                    Write-Verbose -Message 'Scanning the Event viewer logs for drivers'
                    $DriverFilesObj = Get-SystemDriver -Audit

                    Write-Verbose -Message 'Creating a policy xml file from the driver files'
                    New-CIPolicy -MultiplePolicyFormat -Level FilePublisher -Fallback None -FilePath '.\DriverFilesScanPolicy.xml' -DriverFiles $DriverFilesObj
                }
                
                Write-Verbose -Message 'Not trusting the policy xml file made before restart, so building the same policy again after restart, this time in Enforced mode instead of Audit mode'
                Copy-Item -Path "$ModuleRootPath\Resources\WDAC Policies\DefaultWindows_Enforced_Kernel_NoFlights.xml" -Destination '.\DefaultWindows_Enforced_Kernel_NoFlights.xml' -Force

                Write-Verbose -Message 'Merging the base policy with the policy made from driver files, to deploy them as one policy'
                Merge-CIPolicy -PolicyPaths '.\DefaultWindows_Enforced_Kernel_NoFlights.xml', '.\DriverFilesScanPolicy.xml' -OutputFilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' | Out-Null

                Write-Verbose -Message 'Removing the old policy again because we used it in merge and do not need it anymore'
                Remove-Item -Path '.\DefaultWindows_Enforced_Kernel_NoFlights.xml' -Force

                Write-Verbose -Message 'Moving all AllowedSigners from Usermode to Kernel mode signing scenario'
                Move-UserModeToKernelMode -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' | Out-Null

                Write-Verbose -Message 'Setting the GUIDs for the XML policy file'
                Edit-GUIDs -PolicyIDInput $PolicyID -PolicyFilePathInput '.\Final_DefaultWindows_Enforced_Kernel.xml'

                Write-Verbose -Message 'Setting a new policy name with the current date attached to it'
                Set-CIPolicyIdInfo -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -PolicyName "Strict Kernel No Flights mode policy Enforced - $(Get-Date -Format 'MM-dd-yyyy')"

                Write-Verbose -Message 'Setting the policy version to 1.0.0.0'
                Set-CIPolicyVersion -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Version '1.0.0.0'

                Write-Verbose -Message 'Setting policy rule options for the final Enforced mode policy'
                @(2, 4, 6, 16, 17, 20) | ForEach-Object -Process { Set-RuleOption -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Option $_ }
                @(0, 3, 8, 9, 10, 11, 12, 13, 14, 15, 18, 19) | ForEach-Object -Process { Set-RuleOption -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Option $_ -Delete }

                if ($EVSigners) {
                    Write-Verbose -Message 'Adding EVSigners policy rule option'
                    Set-RuleOption -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -Option 8
                }
                
                Write-Verbose -Message 'Setting the HVCI to Strict'
                Set-HVCIOptions -Strict -FilePath '.\Final_DefaultWindows_Enforced_Kernel.xml'

                # Deploy the policy if Deploy parameter is used
                if ($Deploy) {
                    Write-Verbose -Message 'Converting the policy XML file to CIP binary'
                    ConvertFrom-CIPolicy -XmlFilePath '.\Final_DefaultWindows_Enforced_Kernel.xml' -BinaryFilePath "$PolicyID.cip" | Out-Null
                    
                    Write-Verbose -Message 'Deploying the enforced mode policy with the same ID as the Audit mode policy, effectively overwriting it'
                    &'C:\Windows\System32\CiTool.exe' --update-policy "$PolicyID.cip" -json | Out-Null
                    Write-ColorfulText -Color Pink -InputText 'Strict Kernel mode policy with no flighting root certs has been deployed in Enforced mode, no restart required.'

                    Write-Verbose -Message 'Removing the GUID of the StrictKernelNoFlightRootsPolicy from user configuration'
                    Remove-CommonWDACConfig -StrictKernelNoFlightRootsPolicyGUID | Out-Null
                }
                else {
                    # Remove the Audit mode policy from the system
                    # This step is necessary if user didn't use the -Deploy parameter
                    # And instead wants to first Sign and then deploy it using the Deploy-SignedWDACConfig cmdlet
                    Write-Verbose -Message 'Removing the deployed Audit mode policy from the system since -Deploy parameter was not used to overwrite it with the enforced mode policy.'
                    &'C:\Windows\System32\CiTool.exe' --remove-policy "{$PolicyID}" -json | Out-Null
                    Write-ColorfulText -Color Pink -InputText 'Strict Kernel mode Enforced policy with no flighting root certs has been created in the current working directory.'
                }
                if (!$Debug) {
                    Write-Verbose -Message 'Removing the DriverFilesScanPolicy.xml and the CIP file because -Debug parameter was not used'
                    Remove-Item -Path ".\$PolicyID.cip", '.\DriverFilesScanPolicy.xml' -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    <#
.SYNOPSIS
    Creates Kernel only mode WDAC policy capable of protecting against BYOVD attacks category
.LINK
    https://github.com/HotCakeX/Harden-Windows-Security/wiki/New%E2%80%90KernelModeWDACConfig
.DESCRIPTION
    Using official Microsoft methods, configure and use Windows Defender Application Control
.COMPONENT
    Windows Defender Application Control, ConfigCI PowerShell module
.FUNCTIONALITY
    Creates Kernel only mode WDAC policy capable of protecting against BYOVD attacks category
.PARAMETER Default
    Creates the strict Kernel mode WDAC policy based off of the default Windows WDAC example policy.
.PARAMETER NoFlightRoots
    Creates the strict Kernel mode WDAC policy based off of the default Windows WDAC example policy, doesn't allow flighting/insider builds.
.PARAMETER PrepMode
    Deploys the Kernel mode WDAC policy in Audit mode so that you can restart your system and start capturing any blocked drivers to be automatically allowed.
.PARAMETER AuditAndEnforce
    Deploys the final Kernel mode WDAC policy in Enforced mode
.PARAMETER EVSigners
    Adds EVSigners policy rule option to the deployed policy. Applicable for both Audit and Enforced modes. Drivers not EV (Extended Validation) signed cannot run nor can they be allowed in a Supplemental policy.
.PARAMETER Deploy
    Deploys the selected policy type instead of just creating it
.PARAMETER SkipVersionCheck
    Can be used with any parameter to bypass the online version check - only to be used in rare cases
.INPUTS
    System.Management.Automation.SwitchParameter
.OUTPUTS
    System.String
#>
}
