Function New-Macros {
    <#
    .SYNOPSIS
        Creates Macros in the CI policy XML and adds them as multi-valued AppIDs to each element in the <FileRules> node
    .PARAMETER XmlFilePath
        The path to the XML file containing the CI policy
    .PARAMETER Macros
        The list of Macros to create. These are the values of the Macros.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param (
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$XmlFilePath,
        [Parameter(Mandatory = $true)][System.String[]]$Macros
    )
    Begin {

        # We don't need duplicate Macros values to exist in the XML policy file
        $Macros = $Macros | Select-Object -Unique

        # Load the XML file
        [System.Xml.XmlDocument]$Xml = Get-Content -Path $XmlFilePath

        # Define the namespace manager
        [System.Xml.XmlNamespaceManager]$Ns = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $Xml.NameTable
        $Ns.AddNamespace('ns', 'urn:schemas-microsoft-com:sipolicy')

        # Find the Macros node
        $MacrosNode = $Xml.SelectSingleNode('//ns:Macros', $Ns)

        # Check if Macros node doesn't exist
        if (($null -eq $MacrosNode ) -and ($MacrosNode -isnot [System.Xml.XmlElement])) {
            # Create the Macros node
            [System.Xml.XmlElement]$MacrosNode = $Xml.CreateElement('Macros', $Xml.DocumentElement.NamespaceURI)
            [System.Void]$Xml.DocumentElement.AppendChild($MacrosNode)
        }

        # Create a hashtable to store the mapping of Macro IDs to their values
        [System.Collections.Hashtable]$MacroAppIDMapping = @{}

        # Ensuring that the MacroIDs are unique - comes handy when merging multiple Macros from different policies into one
        foreach ($Macro in $Macros) {
            $RandomizedGUID = [System.Guid]::NewGuid().ToString().Replace('-', '')
            $MacroAppIDMapping["AppID.$RandomizedGUID"] = $Macro
        }

        # To store the AppIDs array as a single string
        $AppIDsArray = $null
    }
    Process {

        foreach ($Macro in $MacroAppIDMapping.Keys) {

            # Create new Macro node
            [System.Xml.XmlElement]$NewMacroNode = $Xml.CreateElement('Macro', $MacrosNode.NamespaceURI)
            # It is important for the ID to be "Id" and not "ID" like the rest of the elements to be valid against the Schema
            $NewMacroNode.SetAttribute('Id', $Macro)
            $NewMacroNode.SetAttribute('Value', $MacroAppIDMapping[$Macro])
            # Add the new node to the Macros node
            [System.Void]$MacrosNode.AppendChild($NewMacroNode)

            [System.String]$AppIDsArray += "`$($Macro)"
        }

        # Update AppIDs for elements between <FileRules> and </FileRules>
        $FileRulesNode = $Xml.SelectSingleNode('//ns:FileRules', $Ns)
        if ($FileRulesNode) {
            # Make sure to exclude the .exe files from the AppIDs because only AddIns such as DLLs should have the AppIDs applied to them.
            # AppIDs applied to .exe files make them unrunnable and trigger blocked event.
            # Also exclude .sys files since driver load can only be done by secure kernel

            # '.*\.(exe|sys)\s(FileRule|FileAttribute|Hash).*'
            $FileRulesToModify = $FileRulesNode.ChildNodes | Where-Object -FilterScript { ($_.Name -in 'Allow', 'Deny', 'FileAttrib', 'FileRule') -and ($_.FriendlyName -notmatch '.*\.(exe|sys).*') }

            $FileRulesToModify | ForEach-Object -Process {
                $_.SetAttribute('AppIDs', [System.String]$AppIDsArray)
            }
        }
    }
    End {
        # Save the modified XML back to the file
        $Xml.Save($XmlFilePath)
    }
}
Export-ModuleMember -Function 'New-Macros'

# SIG # Begin signature block
# MIILkgYJKoZIhvcNAQcCoIILgzCCC38CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCcFJ75W21W9LA9
# H+FtuAuLcq9qu0K52J0LP15tFIqdnqCCB9AwggfMMIIFtKADAgECAhMeAAAABI80
# LDQz/68TAAAAAAAEMA0GCSqGSIb3DQEBDQUAME8xEzARBgoJkiaJk/IsZAEZFgNj
# b20xIjAgBgoJkiaJk/IsZAEZFhJIT1RDQUtFWC1DQS1Eb21haW4xFDASBgNVBAMT
# C0hPVENBS0VYLUNBMCAXDTIzMTIyNzExMjkyOVoYDzIyMDgxMTEyMTEyOTI5WjB5
# MQswCQYDVQQGEwJVSzEeMBwGA1UEAxMVSG90Q2FrZVggQ29kZSBTaWduaW5nMSMw
# IQYJKoZIhvcNAQkBFhRob3RjYWtleEBvdXRsb29rLmNvbTElMCMGCSqGSIb3DQEJ
# ARYWU3B5bmV0Z2lybEBvdXRsb29rLmNvbTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAKb1BJzTrpu1ERiwr7ivp0UuJ1GmNmmZ65eckLpGSF+2r22+7Tgm
# pEifj9NhPw0X60F9HhdSM+2XeuikmaNMvq8XRDUFoenv9P1ZU1wli5WTKHJ5ayDW
# k2NP22G9IPRnIpizkHkQnCwctx0AFJx1qvvd+EFlG6ihM0fKGG+DwMaFqsKCGh+M
# rb1bKKtY7UEnEVAsVi7KYGkkH+ukhyFUAdUbh/3ZjO0xWPYpkf/1ldvGes6pjK6P
# US2PHbe6ukiupqYYG3I5Ad0e20uQfZbz9vMSTiwslLhmsST0XAesEvi+SJYz2xAQ
# x2O4n/PxMRxZ3m5Q0WQxLTGFGjB2Bl+B+QPBzbpwb9JC77zgA8J2ncP2biEguSRJ
# e56Ezx6YpSoRv4d1jS3tpRL+ZFm8yv6We+hodE++0tLsfpUq42Guy3MrGQ2kTIRo
# 7TGLOLpayR8tYmnF0XEHaBiVl7u/Szr7kmOe/CfRG8IZl6UX+/66OqZeyJ12Q3m2
# fe7ZWnpWT5sVp2sJmiuGb3atFXBWKcwNumNuy4JecjQE+7NF8rfIv94NxbBV/WSM
# pKf6Yv9OgzkjY1nRdIS1FBHa88RR55+7Ikh4FIGPBTAibiCEJMc79+b8cdsQGOo4
# ymgbKjGeoRNjtegZ7XE/3TUywBBFMf8NfcjF8REs/HIl7u2RHwRaUTJdAgMBAAGj
# ggJzMIICbzA8BgkrBgEEAYI3FQcELzAtBiUrBgEEAYI3FQiG7sUghM++I4HxhQSF
# hqV1htyhDXuG5sF2wOlDAgFkAgEIMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1Ud
# DwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYB
# BQUHAwMwHQYDVR0OBBYEFOlnnQDHNUpYoPqECFP6JAqGDFM6MB8GA1UdIwQYMBaA
# FICT0Mhz5MfqMIi7Xax90DRKYJLSMIHUBgNVHR8EgcwwgckwgcaggcOggcCGgb1s
# ZGFwOi8vL0NOPUhPVENBS0VYLUNBLENOPUhvdENha2VYLENOPUNEUCxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPU5vbkV4aXN0ZW50RG9tYWluLERDPWNvbT9jZXJ0aWZpY2F0ZVJldm9jYXRp
# b25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwgccG
# CCsGAQUFBwEBBIG6MIG3MIG0BggrBgEFBQcwAoaBp2xkYXA6Ly8vQ049SE9UQ0FL
# RVgtQ0EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZp
# Y2VzLENOPUNvbmZpZ3VyYXRpb24sREM9Tm9uRXhpc3RlbnREb21haW4sREM9Y29t
# P2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0
# aG9yaXR5MA0GCSqGSIb3DQEBDQUAA4ICAQA7JI76Ixy113wNjiJmJmPKfnn7brVI
# IyA3ZudXCheqWTYPyYnwzhCSzKJLejGNAsMlXwoYgXQBBmMiSI4Zv4UhTNc4Umqx
# pZSpqV+3FRFQHOG/X6NMHuFa2z7T2pdj+QJuH5TgPayKAJc+Kbg4C7edL6YoePRu
# HoEhoRffiabEP/yDtZWMa6WFqBsfgiLMlo7DfuhRJ0eRqvJ6+czOVU2bxvESMQVo
# bvFTNDlEcUzBM7QxbnsDyGpoJZTx6M3cUkEazuliPAw3IW1vJn8SR1jFBukKcjWn
# aau+/BE9w77GFz1RbIfH3hJ/CUA0wCavxWcbAHz1YoPTAz6EKjIc5PcHpDO+n8Fh
# t3ULwVjWPMoZzU589IXi+2Ol0IUWAdoQJr/Llhub3SNKZ3LlMUPNt+tXAs/vcUl0
# 7+Dp5FpUARE2gMYA/XxfU9T6Q3pX3/NRP/ojO9m0JrKv/KMc9sCGmV9sDygCOosU
# 5yGS4Ze/DJw6QR7xT9lMiWsfgL96Qcw4lfu1+5iLr0dnDFsGowGTKPGI0EvzK7H+
# DuFRg+Fyhn40dOUl8fVDqYHuZJRoWJxCsyobVkrX4rA6xUTswl7xYPYWz88WZDoY
# gI8AwuRkzJyUEA07IYtsbFCYrcUzIHME4uf8jsJhCmb0va1G2WrWuyasv3K/G8Nn
# f60MsDbDH1mLtzGCAxgwggMUAgEBMGYwTzETMBEGCgmSJomT8ixkARkWA2NvbTEi
# MCAGCgmSJomT8ixkARkWEkhPVENBS0VYLUNBLURvbWFpbjEUMBIGA1UEAxMLSE9U
# Q0FLRVgtQ0ECEx4AAAAEjzQsNDP/rxMAAAAAAAQwDQYJYIZIAWUDBAIBBQCggYQw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQx
# IgQgpOULMfADBNWI4yzW3vcrcF4Ieu92xYo05RkKfv0ItQMwDQYJKoZIhvcNAQEB
# BQAEggIAi7bco+4CM93LePkPged9B9cHohLBYZT8wVj0UsuxAbrenuBdHhwg8O+R
# E0gtFu99XBa1f++C4JXsRdEoXtvIzYNr3X8oCjD1kX4ZsnZYihi+yCksbO2Evwm2
# I5T/6duYKpp/uPdFLNoLNUNOzFa1qtswgxKVkepXUBFWvtDH6Q64s903i26ES5XY
# IT7ZUu7TVzLvZ+YpEIJBnSacyXAcW5xEAbVt1fV131fAF8CZz3RAN39u7m/t+rdM
# HCQmSLJvCbThLPiMwTDyVjarC8RogNXcPNyNDM2nLZsS3R1p6807audtEEzs/L7I
# i0IZyYTPpWSmTwufAwuUI34roiTpWItWNEsqdyIr0NnDlz9vQO3rG+NMG0ySBSNt
# ORlxRMPW4++SnEmVcaxxCd/2aqMAL6s1tTUkiR4KyD2O5P5CF1xBeIB6eBmIee9c
# Cyzdbona86WqsZNOeo96kwCAwTqeipWyz3rua3/qO4jSF6O2uAxpIrGP5BEXnSJ1
# ChFZsrIsL2PdEhMyjGbxUjQZ+Qngw2cgFKFNruVRS2aZnBLH0yEbWNFIAC8SCPki
# uQT77b/PCGj+0pgbVfL/sUYsUTZnAgjHDm41xIPrVQkYtSxnNxOWgFZouY+xYiqM
# vERAj/2+dJI/2umFvhtytN4CrEe7J2G4P4R+mIZqQPaujZJ+k5g=
# SIG # End signature block
