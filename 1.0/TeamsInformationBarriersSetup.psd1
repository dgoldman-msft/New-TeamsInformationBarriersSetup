@{
    RootModule        = 'TeamsInformationBarriersSetup.psm1'
    ModuleVersion     = '1.0'
    GUID              = 'de14f0d2-f4c1-4f37-b876-d0d4f3f6f2df'
    Author            = 'Dave Goldman'
    CompanyName       = ''
    Copyright         = '(c) Dave Goldman. All rights reserved.'
    Description       = 'Creates and configures an Information Barrier lab for Teams in Microsoft 365.'
    PowerShellVersion = '7.1'

    FunctionsToExport = @('New-TeamsInformationBarriersSetup')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('TIBS')

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft365', 'Purview', 'InformationBarrier', 'ExchangeOnline', 'Graph', 'Teams')
            ProjectUri   = 'https://github.com/microsoft/TeamsInformationBarriersSetup'
            LicenseUri   = 'https://github.com/dgoldman-msft/TeamsInformationBarriersSetup/blob/main/LICENSE'
            ReleaseNotes = '1.0 - Initial release'
        }
    }
}
