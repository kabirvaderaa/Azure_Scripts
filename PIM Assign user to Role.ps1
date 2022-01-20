
#Install-module AzureADPreview
#Import-Module AzureADPreview



Connect-AzureAD
Connect-AzAccount


#Select a Subscription to pull back Roles
$subscription = "<Your Subscription>"  
select-azsubscription -SubscriptionName $subscription


#Varables
#######################
$managementgroup = '/providers/Microsoft.Management/managementGroups/<managementgroup id>'  
$Azprovider = 'AzureResources'   # Azure Subscription / Resources
#$ADprovider = 'aadRoles'   #Azure AD 
$GuestEmailAccounts = Import-Csv .\guest_email.csv



#Set Schedule for PIM to Expire in 360
########################################
$messageInfo = New-Object Microsoft.Open.MSGraph.Model.InvitedUserMessageInfo
$schedule = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedSchedule

$schedule.Type = "Once"
$schedule.StartDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$schedule.EndDateTime =  ((Get-Date).AddDays(360)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")


$messageInfo.CustomizedMessageBody = "Please Accept the Invite to Gain Access the <Company X> Azure Tennent for the Access you have requested.  If you do not accept the invitation your requested access and invitation will be revoked in the next 30 days"

#Get the ID of the Management Group / Subscription 
$SubscriptionPIMID = (Get-AzureADMSPrivilegedResource -ProviderId $Azprovider -Filter "ExternalId eq '$managementgroup'").Id

ForEach ($Guest in $GuestEmailAccounts) {


    #Get the User ID
    $Guestemail = $Guest.email
  
    #Get Object ID from Azure AD
    $targetuserID = (Get-AzureADUser  -Filter "userType eq 'Guest' and otherMails/any(c:c eq '$Guestemail')").ObjectId 
    $roleDefinitionID = (Get-AzRoleDefinition -Name $Guest."Role").Id  # Get role ID 

   #If account does not exisit invite them
   #########################################
    
   if($null -eq $targetuserID)
   {
        #Write-Host "user exisits: $Guestemail"
        Write-Host "send invite $Guestemail"

        New-AzureADMSInvitation -InvitedUserDisplayName $Guest.email `
         -InvitedUserEmailAddress $Guest.email `
         -InviteRedirectURL https://portal.azure.com `
         -InvitedUserMessageInfo $messageInfo `
         -SendInvitationMessage $true             

         Start-Sleep 15   #pause 15 seconds to before getting account details as the account ID takes a few seconds

        $targetuserID = (Get-AzureADUser  -Filter "otherMails/any(c:c eq '$Guestemail')").ObjectId   # user is not marked as guest until after acceptance
   
    }

      Write-Host "$Guestemail ObjectID= $targetuserID"

    

    #If Permission is PIM then apply permission as Eligible otherwise grant permanant access on management group
    if ($Guest.pim -eq "yes")
    {
      Write-Host "PIM USER: $Guestemail for role $Guest.Role"
    #Apply the user as Eligible for the role
    Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId $Azprovider `
        -ResourceId $SubscriptionPIMID `
        -RoleDefinitionId $roleDefinitionID `
        -SubjectId $targetuserID `
        -Type 'adminAdd' `
        -AssignmentState 'Eligible' `
        -schedule $schedule `
        -reason $Guest."reason"
    
    }
    else
    {
      Write-Host "Assign Permanent Access: $Guestemail for role $Guest.Role"
    
        New-AzRoleAssignment -ObjectId $targetuserID `
            -RoleDefinitionName $Guest.Role `
            -Scope $managementgroup

    }


} # end loop
