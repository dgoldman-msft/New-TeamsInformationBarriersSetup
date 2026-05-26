# Dot-source all internal helper functions
Get-ChildItem -Path (Join-Path $PSScriptRoot 'internal\functions') -Filter '*.ps1' -File |
	Sort-Object -Property Name |
	ForEach-Object { . $_.FullName }

# Dot-source all public functions
Get-ChildItem -Path (Join-Path $PSScriptRoot 'functions') -Filter '*.ps1' -File |
	Sort-Object -Property Name |
	ForEach-Object { . $_.FullName }

# Export public function and alias
Set-Alias -Name TIBS -Value New-TeamsInformationBarriersSetup -Scope Script
Export-ModuleMember -Function 'New-TeamsInformationBarriersSetup' -Alias 'TIBS'
