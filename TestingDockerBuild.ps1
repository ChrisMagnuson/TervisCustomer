$ModuleName = "TervisCustomer"
$TervisModuleDependencies = "InvokeSQL",
    "OracleE-BusinessSuitePowerShell",
    "PasswordstatePowerShell",
    "TervisMicrosoft.PowerShell.Utility",
    "TervisOracleE-BusinessSuitePowerShell",
    "TervisPasswordstatePowerShell",
    "TervisGithub",
    "TervisUniversalDashboard",
    "WebServicesPowerShellProxyBuilder",
    "TervisMicrosoft.PowerShell.Security",
    "TervisCustomer"
$EnvironmentName = "Production"
$PowerShellGalleryDependencies = @{
        Name = "powershell-yaml"
    }, 
    @{
            Name = "UniversalDashboard"
            RequiredVersion="2.2.1"
    } 
$PowerShellNugetDependencies = @{
			Name = "Oracle.ManagedDataAccess.Core"
		},
		@{
			Name = "libphonenumber-csharp"
			SkipDependencies = $true
        } 
$CommandString = @"
# Hopefully the below is not still needed, if it is we will have to figure out a way to import the correct directory that contains UD
#`$CacheDrive = Get-PSDrive -Name Cache -ErrorAction SilentlyContinue
#if (-not `$CacheDrive) {
#	Import-Module UniversalDashboard
#}

if (-Not `$Cache:EBSPowershellConfiguration ) {
	`$Cache:EBSPowershellConfiguration = Get-TervisEBSPowershellConfiguration -Name $EnvironmentName
}

Set-EBSPowershellConfiguration -Configuration `$Cache:EBSPowershellConfiguration
Invoke-TervisCustomerSearchDashboard
"@ 
$UseTLS = $true
$PasswordStatePasswordGUID  
$Port = 10000


$PowerShellApplicationFilesParameters = @{
    ModuleName = "TervisCustomer"
TervisModuleDependencies = "InvokeSQL",
    "OracleE-BusinessSuitePowerShell",
    "PasswordstatePowerShell",
    "TervisMicrosoft.PowerShell.Utility",
    "TervisOracleE-BusinessSuitePowerShell",
    "TervisPasswordstatePowerShell",
    "TervisGithub",
    "TervisUniversalDashboard",
    "WebServicesPowerShellProxyBuilder",
    "TervisMicrosoft.PowerShell.Security",
    "TervisCustomer"
EnvironmentName = "Production"
PowerShellGalleryDependencies = @{
        Name = "powershell-yaml"
    }, 
    @{
            Name = "UniversalDashboard"
            RequiredVersion="2.2.1"
    } 
PowerShellNugetDependencies = @{
			Name = "Oracle.ManagedDataAccess.Core"
		},
		@{
			Name = "libphonenumber-csharp"
			SkipDependencies = $true
        } 
CommandString = @"
# Hopefully the below is not still needed, if it is we will have to figure out a way to import the correct directory that contains UD
#`$CacheDrive = Get-PSDrive -Name Cache -ErrorAction SilentlyContinue
#if (-not `$CacheDrive) {
#	Import-Module UniversalDashboard
#}

if (-Not `$Cache:EBSPowershellConfiguration ) {
	`$Cache:EBSPowershellConfiguration = Get-TervisEBSPowershellConfiguration -Name $EnvironmentName
}

Set-EBSPowershellConfiguration -Configuration `$Cache:EBSPowershellConfiguration
Invoke-TervisCustomerSearchDashboard
"@ 
}