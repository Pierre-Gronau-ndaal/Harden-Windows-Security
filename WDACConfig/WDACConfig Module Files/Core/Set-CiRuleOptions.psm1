Function Set-CiRuleOptions {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([System.Void])]
    param (
        [ValidateSet('Base', 'BaseISG', 'BaseKernel', 'Supplemental')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Template')]
        [System.String]$Template,

        [ValidateScript({ Test-CiPolicy -XmlFile $_ })]
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$FilePath,

        [ValidateScript({
                if ($_ -notin [RuleOptionsx]::new().GetValidValues()) { throw "Invalid Policy Rule Option: $_" }
                # Return true if everything is okay
                $true
            })]
        [Parameter(Mandatory = $false)][System.String[]]$RulesToAdd,

        [ValidateScript({
                if ($_ -notin [RuleOptionsx]::new().GetValidValues()) { throw "Invalid Policy Rule Option: $_" }
                # Return true if everything is okay
                $true
            })]
        [Parameter(Mandatory = $false)][System.String[]]$RulesToRemove,

        [Parameter(Mandatory = $false)][System.Boolean]$RequireWHQL,
        [Parameter(Mandatory = $false)][System.Boolean]$EnableAuditMode,
        [Parameter(Mandatory = $false)][System.Boolean]$DisableFlightSigning,
        [Parameter(Mandatory = $false)][System.Boolean]$RequireEVSigners,
        [Parameter(Mandatory = $false)][System.Boolean]$ScriptEnforcement,
        [Parameter(Mandatory = $false)][System.Boolean]$TestMode,

        [Parameter(Mandatory = $false, ParameterSetName = 'RemoveAll')]
        [System.Management.Automation.SwitchParameter]$RemoveAll
    )
    Begin {
        [System.Boolean]$Verbose = $PSBoundParameters.Verbose.IsPresent ? $true : $false
        . "$([WDACConfig.GlobalVars]::ModuleRootPath)\CoreExt\PSDefaultParameterValues.ps1"

        Import-Module -FullyQualifiedName "$([WDACConfig.GlobalVars]::ModuleRootPath)\XMLOps\Close-EmptyXmlNodes_Semantic.psm1" -Force

        Write-Verbose -Message "Set-CiRuleOptions: Configuring the policy rule options for: $($FilePath.Name)"

        [System.Collections.Hashtable]$Intel = ConvertFrom-Json -AsHashtable -InputObject (Get-Content -Path "$([WDACConfig.GlobalVars]::ModuleRootPath)\Resources\PolicyRuleOptions.Json" -Raw)

        # Load the XML file
        [System.Xml.XmlDocument]$Xml = Get-Content -Path $FilePath

        # Define the namespace manager
        [System.Xml.XmlNamespaceManager]$Ns = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $Xml.NameTable
        $Ns.AddNamespace('ns', 'urn:schemas-microsoft-com:sipolicy')

        # Find the Rules Node
        [System.Xml.XmlElement]$RulesNode = $Xml.SelectSingleNode('//ns:Rules', $Ns)

        # an empty hashtable to store the existing rule options in the XML policy file
        [System.Collections.Hashtable]$ExistingRuleOptions = @{}

        # The final rule options to implement which contains only unique values
        $RuleOptionsToImplement = [System.Collections.Generic.HashSet[System.Int32]] @()

        # Defining the rule options for each policy type and scenario
        $BaseRules = [System.Collections.Generic.HashSet[System.Int32]] @(0, 2, 5, 6, 11, 12, 16, 17, 19, 20)
        $BaseISGRules = [System.Collections.Generic.HashSet[System.Int32]] @(0, 2, 5, 6, 11, 12, 14, 15, 16, 17, 19, 20)
        $BaseKernelModeRules = [System.Collections.Generic.HashSet[System.Int32]] @(2, 5, 6, 16, 17, 20)
        $SupplementalRules = [System.Collections.Generic.HashSet[System.Int32]] @(6, 18)
        $RequireWHQLRules = [System.Collections.Generic.HashSet[System.Int32]] @(2)
        $EnableAuditModeRules = [System.Collections.Generic.HashSet[System.Int32]] @(3)
        $DisableFlightSigningRules = [System.Collections.Generic.HashSet[System.Int32]] @(4)
        $RequireEVSignersRules = [System.Collections.Generic.HashSet[System.Int32]] @(8)
        $ScriptEnforcementRules = [System.Collections.Generic.HashSet[System.Int32]] @(11)
        $TestModeRules = [System.Collections.Generic.HashSet[System.Int32]] @(9, 10)

        # A flag to determine whether to clear all the existing rules based on the input parameters
        if ($PSBoundParameters['Template'] -or $PSBoundParameters['RemoveAll']) {
            [System.Boolean]$ClearAllRules = $true
        }
        else {
            [System.Boolean]$ClearAllRules = $False
        }

        # Iterating through each <Rule> node in the supplied XML file
        foreach ($RuleNode in $RulesNode.SelectNodes('ns:Rule', $Ns)) {
            # Get the option text from the <Option> node
            [System.String]$OptionText = $RuleNode.SelectSingleNode('ns:Option', $Ns).InnerText

            # Check if the option text exists in the Intel HashTable
            if ($Intel.ContainsValue($OptionText)) {

                # Add the option text and its corresponding key to the HashTable
                [System.Int32]$Key = $Intel.Keys | Where-Object -FilterScript { $Intel[$_] -eq $OptionText }
                $ExistingRuleOptions[$Key] = [System.String]$OptionText
            }
        }

        if (-NOT $ClearAllRules -and $ExistingRuleOptions.Keys.Count -gt 0) {
            # Add the existing rule options to the final rule options to implement
            $RuleOptionsToImplement.UnionWith([System.Collections.Generic.HashSet[System.Int32]]@($ExistingRuleOptions.Keys))
        }
        else {
            $RuleOptionsToImplement.Clear()
        }

        # Process selected templates
        switch ($Template) {
            'Base' { $RuleOptionsToImplement.UnionWith($BaseRules) }
            'BaseISG' { $RuleOptionsToImplement.UnionWith($BaseISGRules) }
            'BaseKernel' { $RuleOptionsToImplement.UnionWith($BaseKernelModeRules) }
            'Supplemental' { $RuleOptionsToImplement.UnionWith($SupplementalRules) }
        }

        # Process individual boolean parameters
        switch ($true) {
            { $RequireWHQL -eq $true } { $RuleOptionsToImplement.UnionWith($RequireWHQLRules) }
            { $RequireWHQL -eq $false } { $RuleOptionsToImplement.ExceptWith($RequireWHQLRules) }
            { $EnableAuditMode -eq $true } { $RuleOptionsToImplement.UnionWith($EnableAuditModeRules) }
            { $EnableAuditMode -eq $false } { $RuleOptionsToImplement.ExceptWith($EnableAuditModeRules) }
            { $DisableFlightSigning -eq $true } { $RuleOptionsToImplement.UnionWith($DisableFlightSigningRules) }
            { $DisableFlightSigning -eq $false } { $RuleOptionsToImplement.ExceptWith($DisableFlightSigningRules) }
            { $RequireEVSigners -eq $true } { $RuleOptionsToImplement.UnionWith($RequireEVSignersRules) }
            { $RequireEVSigners -eq $false } { $RuleOptionsToImplement.ExceptWith($RequireEVSignersRules) }
            { $ScriptEnforcement -eq $false } { $RuleOptionsToImplement.UnionWith($ScriptEnforcementRules) }
            { $ScriptEnforcement -eq $true } { $RuleOptionsToImplement.ExceptWith($ScriptEnforcementRules) }
            { $TestMode -eq $true } { $RuleOptionsToImplement.UnionWith($TestModeRules) }
            { $TestMode -eq $false } { $RuleOptionsToImplement.ExceptWith($TestModeRules) }
        }

        # Process individual rules to add
        foreach ($Item in $RulesToAdd) {
            [System.Int32]$Key = $Intel.Keys | Where-Object -FilterScript { $Intel[$_] -eq $Item }
            [System.Void]$RuleOptionsToImplement.Add($Key)
        }
        # Process individual rules to  remove
        foreach ($Item in $RulesToRemove) {
            [System.Int32]$Key = $Intel.Keys | Where-Object -FilterScript { $Intel[$_] -eq $Item }
            [System.Void]$RuleOptionsToImplement.Remove($Key)
        }

        # Make sure Supplemental policies only contain rule options that are applicable to them
        if (($Template -eq 'Supplemental') -or ($Xml.SiPolicy.PolicyType -eq 'Supplemental Policy')) {
            foreach ($Rule in $RuleOptionsToImplement) {
                if ($Rule -notin '18', '14', '13', '7', '5', '6') {
                    [System.Void]$RuleOptionsToImplement.Remove($Rule)
                }
            }
        }
    }
    Process {

        # Compare the existing rule options in the policy XML file with the rule options to implement
        Compare-Object -ReferenceObject ([System.Int32[]]$RuleOptionsToImplement) -DifferenceObject ([System.Int32[]]$ExistingRuleOptions.Keys) |
        ForEach-Object -Process {
            if ($_.SideIndicator -eq '<=') {
                Write-Verbose -Message "Set-CiRuleOptions: Adding Rule Option: $($Intel[[System.String]$_.InputObject])"
            }
            else {
                Write-Verbose -Message "Set-CiRuleOptions: Removing Rule Option: $($Intel[[System.String]$_.InputObject])"
            }
        }

        # Always remove any existing rule options initially. The calculations determining which
        # Rules must be included in the policy are all made in the Begin block.
        if ($null -ne $RulesNode) {
            $RulesNode.RemoveAll()
        }

        # Create new Rule elements
        foreach ($Rule in ($RuleOptionsToImplement | Sort-Object)) {

            # Create a new rule element
            [System.Xml.XmlElement]$NewRuleNode = $Xml.CreateElement('Rule', $RulesNode.NamespaceURI)

            # Create the Option element inside of the rule element
            [System.Xml.XmlElement]$OptionNode = $Xml.CreateElement('Option', $RulesNode.NamespaceURI)
            # Set the value of the Option element
            $OptionNode.InnerText = $Intel[[System.String]$Rule]
            # Append the Option element to the Rule element
            [System.Void]$NewRuleNode.AppendChild($OptionNode)

            # Add the new Rule element to the Rules node
            [System.Void]$RulesNode.AppendChild($NewRuleNode)
        }
    }
    End {
        $Xml.Save($FilePath)

        # Close the empty XML nodes
        Close-EmptyXmlNodes_Semantic -XmlFilePath $FilePath

        # Set the HVCI to Strict
        Set-HVCIOptions -Strict -FilePath $FilePath

        # Validate the XML file at the end
        $null = Test-CiPolicy -XmlFile $FilePath
    }
    <#
    .SYNOPSIS
        Configures the Policy rule options in a given XML file and sets the HVCI to Strict in the output XML file.
        This function is completely self-sufficient and does not rely on built-in modules.
    .DESCRIPTION
        It offers many ways to configure the policy rule options in a given XML file.
        All of its various parameters provide the flexibility that ensures only one pass is needed to configure the policy rule options.
    .LINK
        https://github.com/HotCakeX/Harden-Windows-Security/wiki/Set-CiRuleOptions
    .PARAMETER Template
        Specifies the template to use for the CI policy rules: Base, BaseISG, BaseKernel, or Supplemental
    .PARAMETER RulesToAdd
        Specifies the rule options to add to the policy XML file
        If a rule option is already selected by the RulesToRemove parameter, it won't be suggested by the argument completer of this parameter.
    .PARAMETER RulesToRemove
        Specifies the rule options to remove from the policy XML file
        If a rule option is already selected by the RulesToAdd parameter, it won't be suggested by the argument completer of this parameter.
    .PARAMETER RemoveAll
        Removes all the existing rule options from the policy XML file
    .PARAMETER FilePath
        Specifies the path to the XML file that contains the CI policy rules
    .PARAMETER RequireWHQL
        Specifies whether to require WHQL signatures for all drivers
    .PARAMETER EnableAuditMode
        Specifies whether to enable audit mode
    .PARAMETER DisableFlightSigning
        Specifies whether to disable flight signing
    .PARAMETER RequireEVSigners
        Specifies whether to require EV signers
    .PARAMETER DisableScriptEnforcement
        Specifies whether to disable script enforcement
    .PARAMETER TestMode
        Specifies whether to enable test mode
    .NOTES
        First the template is processed, then the individual boolean parameters, and finally the individual rules to add and remove.
    .INPUTS
        System.Management.Automation.SwitchParameter
        System.IO.FileInfo
        System.String[]
        System.String
    .OUTPUTS
        System.Void
    #>
}
# Note: This argument completer suggest rule options that are not already selected on the command line by *any* other parameter
# It currently doesn't make a distinction between the RulesToAdd/RulesToRemove parameters and other parameters.
[System.Management.Automation.ScriptBlock]$RuleOptionsScriptBlock = {
    # Get the current command and the already bound parameters
    param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)

    # Find all string constants in the AST
    $Existing = $CommandAst.FindAll(
        # The predicate scriptblock to define the criteria for filtering the AST nodes
        {
            $Args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
        },
        # The recurse flag, whether to search nested scriptblocks or not.
        $false
    ).Value

    foreach ($Item in ([RuleOptionsx]::new().GetValidValues())) {
        # Check if the item is already selected
        if ($Item -notin $Existing) {
            # Return the item
            "'$Item'"
        }
    }
}

Register-ArgumentCompleter -CommandName 'Set-CiRuleOptions' -ParameterName 'FilePath' -ScriptBlock ([WDACConfig.ArgumentCompleters]::ArgumentCompleterXmlFilePathsPicker)
Register-ArgumentCompleter -CommandName 'Set-CiRuleOptions' -ParameterName 'RulesToAdd' -ScriptBlock $RuleOptionsScriptBlock
Register-ArgumentCompleter -CommandName 'Set-CiRuleOptions' -ParameterName 'RulesToRemove' -ScriptBlock $RuleOptionsScriptBlock
