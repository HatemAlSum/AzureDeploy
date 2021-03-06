param ($collectAuditLogs,$collectionFromAllSubscriptions)

#region Login to Azure account and select the subscription.
#Authenticate to Azure with SPN section
"Logging in to Azure..."

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$SelectedAzureSub = Select-AzureRmSubscription -SubscriptionId $servicePrincipalConnection.SubscriptionId -TenantId $servicePrincipalConnection.tenantid 


#cheking if ASM Runas Account exist
   
	try
    {
        $AsmConn = Get-AutomationConnection -Name AzureClassicRunAsConnection -ea 0
       
    }
    Catch
    {
        if ($AsmConn -eq $null) {
            Write-Warning "Could not retrieve connection asset AzureClassicRunAsConnection. Ensure that runas account exist and valid in the Automation account."
            $getAsmHeader=$false
        }
    }
     if ($AsmConn -eq $null) {
        Write-Warning "Could not retrieve connection asset AzureClassicRunAsConnection. Ensure that runas account exist and valid in the Automation account. Quota usage infomration for classic accounts will no tbe collected"
        $getAsmHeader=$false
    }Else
	{
			$getAsmHeader=$true
    }



#endregion

$AAResourceGroup = Get-AutomationVariable -Name 'AzureSAIngestion-AzureAutomationResourceGroup-MS-Mgmt-SA'
$AAAccount = Get-AutomationVariable -Name 'AzureSAIngestion-AzureAutomationAccount-MS-Mgmt-SA'
$MetricsRunbookName = "AzureSAIngestionMetrics-MS-Mgmt-SA"
$MetricsScheduleName = "AzureStorageMetrics-Schedule"
$LogsRunbookName="AzureSAIngestionLogs-MS-Mgmt-SA"
$LogsScheduleName = "AzureStorageLogs-HourlySchedule"
$MetricsEnablerRunbookName = "AzureSAMetricsEnabler-MS-Mgmt-SA"
$MetricsEnablerScheduleName = "AzureStorageMetricsEnabler-DailySchedule"
$mainSchedulerName="AzureSA-Scheduler-Hourly"

$varText= "AAResourceGroup = $AAResourceGroup , AAAccount = $AAAccount"

Write-output $varText


New-AzureRmAutomationVariable -Name varVMIopsList -Description "Variable to store IOPS limits for Azure VM Sizes." -Value $vmiolimits -Encrypted 0 -ResourceGroupName $AAResourceGroup -AutomationAccountName $AAAccount  -ea 0

IF([string]::IsNullOrEmpty($AAAccount) -or [string]::IsNullOrEmpty($AAResourceGroup))
{

	Write-Error "Automation Account  or Automation Account Resource Group Variables is empty. Make sure AzureSAIngestion-AzureAutomationAccount-MS-Mgmt-SA and AzureSAIngestion-AzureAutomationResourceGroup-MS-Mgmt-SA variables exist in automation account and populated. "
	Write-Output "Script will not continue"
	Exit


}


$min=(get-date).Minute 
if($min -in 0..10) 
{
	$RBStart1=(get-date -Minute 16 -Second 00).ToUniversalTime()
}Elseif($min -in 11..25) 
{
	$RBStart1=(get-date -Minute 31 -Second 00).ToUniversalTime()
}elseif($min -in 26..40) 
{
	$RBStart1=(get-date -Minute 46 -Second 00).ToUniversalTime()
}ElseIf($min -in 46..55) 
{
	$RBStart1=(get-date -Minute 01 -Second 00).AddHours(1).ToUniversalTime()
}Else
{
	$RBStart1=(get-date -Minute 16 -Second 00).AddHours(1).ToUniversalTime()
}

$RBStart2=$RBStart1.AddMinutes(15)
$RBStart3=$RBStart2.AddMinutes(15)
$RBStart4=$RBStart3.AddMinutes(15)


# First clean up any previous schedules to prevent any conflict 

$allSchedules=Get-AzureRmAutomationSchedule `
-AutomationAccountName $AAAccount `
-ResourceGroupName $AAResourceGroup

foreach ($sch in  $allSchedules|where{$_.Name -match $MetricsScheduleName -or $_.Name -match $MetricsEnablerScheduleName -or $_.Name -match $LogsScheduleName })
{

	Write-output "Removing Schedule $($sch.Name)    "
	Remove-AzureRmAutomationSchedule `
	-AutomationAccountName $AAAccount `
	-Force `
	-Name $sch.Name `
	-ResourceGroupName $AAResourceGroup `
	
} 

Write-output  "Creating schedule $MetricsScheduleName for runbook $MetricsRunbookName"

$i=1
Do {
	New-AzureRmAutomationSchedule `
	-AutomationAccountName $AAAccount `
	-HourInterval 1 `
	-Name $($MetricsScheduleName+"-$i") `
	-ResourceGroupName $AAResourceGroup `
	-StartTime (Get-Variable -Name RBStart"$i").Value

	IF ($collectionFromAllSubscriptions  -match 'Enabled')
	{
		$params = @{"collectionFromAllSubscriptions" = $true ; "getAsmHeader"=$getAsmHeader}

		Register-AzureRmAutomationScheduledRunbook `
		-AutomationAccountName $AAAccount `
		-ResourceGroupName  $AAResourceGroup `
		-RunbookName $MetricsRunbookName `
		-ScheduleName $($MetricsScheduleName+"-$i") -Parameters $Params
	}Else
	{

		$params = @{"collectionFromAllSubscriptions" = $false ; "getAsmHeader"=$getAsmHeader}
		Register-AzureRmAutomationScheduledRunbook `
		-AutomationAccountName $AAAccount `
		-ResourceGroupName  $AAResourceGroup `
		-RunbookName $MetricsRunbookName `
		-ScheduleName $($MetricsScheduleName+"-$i")  -Parameters $Params 
	}

	$i++
}
While ($i -le 4)




#Create Schedule for collecting Logs
IF($collectAuditLogs -eq 'Enabled')
{

	#Add the schedule an hour ahead and start the runbook

	$RunbookStartTime = $Date =(get-date -Minute 05 -Second 00).AddHours(1).ToUniversalTime()
	IF (($runbookstarttime-(Get-date).ToUniversalTime()).TotalMinutes -lt 6)
	{
		$RunbookStartTime=((Get-date).ToUniversalTime()).AddMinutes(7)

	}
	Write-Output "Creating schedule $LogsScheduleName for $RunbookStartTime for runbook $LogsRunbookName"

	New-AzureRmAutomationSchedule `
	-AutomationAccountName $AAAccount `
	-HourInterval 1 `
	-Name $LogsScheduleName `
	-ResourceGroupName $AAResourceGroup `
	-StartTime $RunbookStartTime

	IF ($collectionFromAllSubscriptions  -match 'Enabled')
	{
		$params = @{"collectionFromAllSubscriptions" = $true ; "getAsmHeader"=$getAsmHeader}
		Register-AzureRmAutomationScheduledRunbook `
		-AutomationAccountName $AAAccount `
		-ResourceGroupName  $AAResourceGroup `
		-RunbookName $LogsRunbookName `
		-ScheduleName $LogsScheduleName -Parameters $Params

		Start-AzureRmAutomationRunbook -AutomationAccountName $AAAccount -Name $LogsRunbookName -ResourceGroupName $AAResourceGroup -Parameters $Params | out-null
	}Else
	{
		
		$params = @{"collectionFromAllSubscriptions" = $false ; "getAsmHeader"=$getAsmHeader}
		
		Register-AzureRmAutomationScheduledRunbook `
		-AutomationAccountName $AAAccount `
		-ResourceGroupName  $AAResourceGroup `
		-RunbookName $LogsRunbookName `
		-ScheduleName $LogsScheduleName -Parameters $Params

		Start-AzureRmAutomationRunbook -AutomationAccountName $AAAccount -Name $LogsRunbookName -ResourceGroupName $AAResourceGroup | out-null
	}



	
}

# Creating Schedules for enabling MEtrics

$MetricsRunbookStartTime = $Date = [DateTime]::Today.AddHours(2).AddDays(1)

Write-Output "Creating schedule $MetricsEnablerScheduleName for $MetricsRunbookStartTime for runbook $MetricsEnablerRunbookName"

New-AzureRmAutomationSchedule `
-AutomationAccountName $AAAccount `
-DayInterval 1 `
-Name "$MetricsEnablerScheduleName" `
-ResourceGroupName $AAResourceGroup `
-StartTime $MetricsRunbookStartTime


Register-AzureRmAutomationScheduledRunbook `
-AutomationAccountName $AAAccount `
-ResourceGroupName  $AAResourceGroup `
-RunbookName $MetricsEnablerRunbookName `
-ScheduleName "$MetricsEnablerScheduleName"



#finally start the  MEtrics enabled runbook once to enable metrics asap

Start-AzureRmAutomationRunbook -Name $MetricsEnablerRunbookName -ResourceGroupName $AAResourceGroup -AutomationAccountName $AAAccount | out-null

#finally remove the schedule for the createschedules runbook as not needed if all schedules are in place

$allSchedules=Get-AzureRmAutomationSchedule `
		-AutomationAccountName $AAAccount `
		-ResourceGroupName $AAResourceGroup |where{$_.Name -match $MetricsScheduleName -or $_.Name -match $MetricsEnablerScheduleName -or $_.Name -match $LogsScheduleName }


If ($allSchedules.count -ge 5)
{
Write-output "Removing hourly schedule for this runbook as its not needed anymore  "
Remove-AzureRmAutomationSchedule `
		-AutomationAccountName $AAAccount `
		-Force `
		-Name $mainSchedulerName `
		-ResourceGroupName $AAResourceGroup `


}

	

