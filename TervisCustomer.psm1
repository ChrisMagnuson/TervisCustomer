$ModulePath = (Get-Module -ListAvailable TervisCustomer).ModuleBase
. $ModulePath\Definition.ps1

function Find-TervisCustomer {
    param (
        $Address1,
        $PhoneNumber,
        $EmailAddress,
        $Firstame,
        $LastName
    )
	$AddressLinePossibilities = $Address1 | Get-AddressLinePossibility
    Find-EBSCustomerAccountNumber -Address1 $AddressLinePossibilities
}

function Get-AddressSlotCombinations { 
	param (
		$CombinedSlots = @(),
		$SlotsToCombine
	)

	if (-not $SlotsToCombine) {
		$Results.Add($CombinedSlots) | Out-Null
	}

	foreach ($Slot in ($SlotsToCombine | Select-Object -First 1)) {
		if($Slot.Alternative) {
			Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + $Slot.Alternative) -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
			if ($Slot.Alternative.length -lt $Slot.Word.length ) {
				Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + "$($Slot.Alternative).") -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
			} else {
				Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + "$($Slot.Word).") -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
			}
		}
		Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + $Slot.Word) -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
	}
}

function Get-AddressLinePossibility {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$AddressLine
	)
	process {
		$AddressLineWithoutSpecialCharacters = $AddressLine | 
		Remove-StringSpecialCharacter -SpecialCharacterToKeep " "

		$Words = $AddressLineWithoutSpecialCharacters -split " "
		$Slots = $Words | ForEach-Object {
			[PSCustomObject]@{
				Word = $_
				Alternative = ($_ | Get-AddressWordAlternative)
			}
		}
		$Results = New-Object System.Collections.ArrayList
		Get-AddressSlotCombinations -SlotsToCombine $Slots
		$UncasedAddressStrings = $Results | % { $_ -join " "}
		$FinalResults = @()
		$FinalResults += $UncasedAddressStrings | % { (Get-Culture).TextInfo.ToTitleCase($_.Tolower()) }
		$FinalResults += $UncasedAddressStrings | % { $_.Tolower() }
		$FinalResults += $UncasedAddressStrings | % { $_.ToUpper() }
		$FinalResults
	}
}

function Get-AddressWordAlternative {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Word
    )
    process {
        $AddressAlternativesHash[$Word.ToUpper()]
    }
}

function New-TervisCustomerSearchDashboard {
	Get-UDDashboard | Where port -eq 10000 | Stop-UDDashboard

	$Dashboard = New-UDDashboard -Title "Tervis Customer Search" -Content {
		New-UDInput -Title "Select me" -Endpoint {
			param(
				[ValidateSet("Yes", "No", "Don't care")]$Opinion,
				[String]$Address1
			)
			$EBSPowerShellConfiguration = Get-EBSPowershellConfiguration
			if (-Not $EBSPowerShellConfiguration) { Set-TervisEBSEnvironment -Name Delta}

			$Count++
			if ($Address1) {
				$AccountNumber = Find-TervisCustomer -Address1 $Address1
			}
			New-UDInputAction -Toast "You selected: $Opinion $Count $($AccountNumber| out-string)"
			
			if ($AccountNumber) {
				New-UDInputAction -Content @(
					New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)
				)
			}			
		} -FontColor "black"
	}
	Start-UDDashboard -Dashboard $Dashboard -Port 10000 -AllowHttpForLogin

    $dashboard = New-UDDashboard -Title "Tervis Customer Search" -Content {
        New-UDInput -Title "New Work Order" -Id "Form" -DebugEndpoint -Endpoint {
			param (
				$Address1,
				$PhoneNumber,
				$EmailAddress,
				$Firstame,
				$LastName
			)
			$EBSPowerShellConfiguration = Get-EBSPowershellConfiguration
			if (-Not $EBSPowerShellConfiguration) { Set-TervisEBSEnvironment -Name Delta}
			Find-TervisCustomer @PSBoundParameters
		}
    } 
    Start-UDDashboard -Dashboard $Dashboard -Port 10000 -AllowHttpForLogin
}

#https://github.com/lazywinadmin/PowerShell/blob/master/TOOL-Remove-StringSpecialCharacter/Remove-StringSpecialCharacter.ps1
function Remove-StringSpecialCharacter
{
<#
.SYNOPSIS
	This function will remove the special character from a string.
	
.DESCRIPTION
	This function will remove the special character from a string.
	I'm using Unicode Regular Expressions with the following categories
	\p{L} : any kind of letter from any language.
	\p{Nd} : a digit zero through nine in any script except ideographic 
	
	http://www.regular-expressions.info/unicode.html
	http://unicode.org/reports/tr18/
.PARAMETER String
	Specifies the String on which the special character will be removed
.SpecialCharacterToKeep
	Specifies the special character to keep in the output
.EXAMPLE
	PS C:\> Remove-StringSpecialCharacter -String "^&*@wow*(&(*&@"
	wow
.EXAMPLE
	PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*"
	
	wow
.EXAMPLE
	PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*" -SpecialCharacterToKeep "*","_","-"
	wow-_*
.NOTES
	Francois-Xavier Cat
	@lazywinadm
	www.lazywinadmin.com
	github.com/lazywinadmin
#>
	[CmdletBinding()]
	param
	(
		[Parameter(ValueFromPipeline)]
		[ValidateNotNullOrEmpty()]
		[Alias('Text')]
		[System.String[]]$String,
		
		[Alias("Keep")]
		#[ValidateNotNullOrEmpty()]
		[String[]]$SpecialCharacterToKeep
	)
	PROCESS
	{
		IF ($PSBoundParameters["SpecialCharacterToKeep"])
		{
			$Regex = "[^\p{L}\p{Nd}"
			Foreach ($Character in $SpecialCharacterToKeep)
			{
				IF ($Character -eq "-"){
					$Regex +="-"
				} else {
					$Regex += [Regex]::Escape($Character)
				}
				#$Regex += "/$character"
			}
			
			$Regex += "]+"
		} #IF($PSBoundParameters["SpecialCharacterToKeep"])
		ELSE { $Regex = "[^\p{L}\p{Nd}]+" }
		
		FOREACH ($Str in $string)
		{
			Write-Verbose -Message "Original String: $Str"
			$Str -replace $regex, ""
		}
	} #PROCESS
}

