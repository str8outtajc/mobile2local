#!/bin/bash
# Version 1.23 Beta

# Credits
# Rich Trouton for the "meat" of this script
# https://derflounder.wordpress.com/2016/12/21/migrating-ad-mobile-accounts-to-local-user-accounts/
# Rich also credits Patrick Gallagher - MigrateUserHomeToDomainAcct.sh
# https://twitter.com/patgmac
# Rich also credits Lisa Davies
# Kevin Hendricks
# Cocoa Dialog Progress bar example
# http://mstratman.github.io/cocoadialog/examples/progressbar.sh.txt

# Setting IFS Env to only use new lines as field seperator
IFS=$'\n'

####################################
######## Edit this stuff ###########
####################################
log_dir="/Library/Logs/MyCompany"
log_file="mobile2local.log"

# Application (Apple Script friendly) name of your company's VPN application
# See GUI dialog funtions 'openingMessage2' and 'quitAllApps' for how this is used
# Basically - we guide the user to shutting down all apps except those specified in white list
# White list currently set to Self Service, VPN Client (as defined with variable) Finder, Console, Terminal, Atom
# You may need to add even more items to your white list
# But by default - we will simply whitelist Self Service and VPN
myOrgVPN="Our Pathetic VPN"

# Path to your Cocoa Dialog binary
# You don't "have" to install Cocoa Dialog.
# Users just won't see a progress bar when conversion occurs
# Script errors gracefully if you don't have Cocoa Dialog installed
cocoaDialog='/private/tmp/CocoaDialog.app/Contents/MacOS/CocoaDialog'

# Icon Options (Making sure we have a decent icon to use somewhere)
if [ -f /path/to/my/compony/logo/icon/file ]
	then
		dialogIcon="Path:To:My:Company:Logo:Icon:File.png"
elif [ -f /Applications/Self\ Service.app/Contents/Resources/Self\ Service.icns ]
	then
		dialogIcon="Applications:Self Service.app:Contents:Resources:Self Service.icns"
elif [ -f /System/Library/CoreServices/Applications/Directory\ Utility.app/Contents/Resources/DirectoryUtility.icns ]
	then
		dialogIcon="System:Library:CoreServices:Applications:Directory Utility.app:Contents:Resources:DirectoryUtility.icns"
else
	dialogIcon="System:Library:CoreServices:Finder.app:Contents:Resources:Finder.icns"
fi

# Include attributes to delete from local record in array below
# These may need to be adjusted to suit your environment

declare -a attributesToKill=(
cached_groups
cached_auth_policy
CopyTimestamp
AltSecurityIdentities
SMBPrimaryGroupSID
OriginalAuthenticationAuthority
OriginalNodeName
SMBSID
SMBScriptPath
SMBPasswordLastSet
SMBGroupRID
PrimaryNTDomain
MCXSettings
MCXFlags
OriginalHomeDirectory
OriginalNFSHomeDirectory
SMBHome
SMBHomeDrive
"dsAttrTypeNative:original_smb_home"
PrimaryNTDomain
AppleMetaRecordName
AuthenticationAuthority
)

####################################
### Edit items below at own risk ###
####################################

# Other Variables
log_location="$log_dir/$log_file"
currentUser=$(stat -f %Su /dev/console)
currentUserID=$(stat -f %u /dev/console)
currentUserHome=`/usr/bin/dscl . -read /Users/$currentUser NFSHomeDirectory | sed -n 's|.* \(/.*\)|\1|p'`
currentUserDarwinFolders=`sudo -u $currentUser getconf DARWIN_USER_DIR`
homeParentDirectory=`dirname $currentUserHome`
currentUserFirstName=`/usr/bin/dscl . -read /Users/$currentUser FirstName | awk -F ": " '{print $2}'`
currentUserLastName=`/usr/bin/dscl . -read /Users/$currentUser LastName | awk -F ": " '{print $2}'`
OS_VERS_MAJ=`/usr/bin/defaults read /System/Library/CoreServices/SystemVersion ProductVersion | awk -F "." '{ print $2 }'`
computerName=`/usr/sbin/systemsetup -getComputerName`
OS_REV=`/usr/bin/sw_vers -productVersion`

####################################
###########   Set Log  #############
####################################
set_log ()
{
if [ -d $log_dir ]
	then
		log_dir_status="Log Directory already exists."
		/bin/chmod 775 $log_dir
	else
		/bin/mkdir $log_dir
		/usr/sbin/chown 0:80 $log_dir
		/bin/chmod 775 $log_dir
		log_dir_status="Log Directory has been created and secured."
fi
if [ -f $log_location ]
	then
		/bin/cat $log_location | /usr/bin/gzip > "$log_location-`date`.gz"
		/bin/rm -f $log_location
		/usr/bin/touch $log_location
		/usr/sbin/chown 0:80 $log_location
		/bin/chmod 644 $log_location
		archive_status="Previous log has been archived."
	else
		/usr/bin/touch $log_location
		/usr/sbin/chown 0:80 $log_location
		/bin/chmod 644 $log_location
		archive_status="No previous logs have been found."
fi

echo -e "===================================\n===================================\n" >> $log_location
echo `date` >> $log_location
echo "Beginning the \"mobile2local\" script." >> $log_location
echo $log_dir_status >> $log_location
echo $archive_status >> $log_location
echo "A new log file has been created and secured." >> $log_location
echo -e "\nSystem Information: \nComputer Name = $computerName \nOS Version = $OS_REV" >> $log_location
}


#########################################
########## GUI Dialogues ################
#########################################
notMobileAccountDialog ()
{
/usr/bin/osascript << EOT
tell application "Finder"
	activate
	display alert "$currentUser does not appear to be an Active Directory Mobile User account." \
	& return & return & "Unable to continue." as critical \
	buttons {"OK"} default button 1
end tell
EOT
}

diskCheckFailDialog ()
{
	/usr/bin/osascript << EOT
	tell application "Finder"
		activate
		display alert "Error" \
		& return & return & "Your home directory does not appear to be on the startup disk." \
		& return & return & "Unfortunately, this tool is not equipped to handle that scenario." \
		buttons {"OK"} default button 1 as critical
	end tell
EOT
}

openingMessage1 ()
{
openingMessageChoice1=`/usr/bin/osascript << EOT
tell application "Finder"
	activate
	display dialog "This utility will attempt the following:" \
	& return & return & "1. Check current account directory status" \
	& return & "2. Unbind Mac from Active Directory if bound" \
	& return & "3. Convert AD account to a standard local account" \
	& return & return & "NOTE: Please reboot your Mac after this process has completed"\
	& return & return & "WARNING: DO NOT REBOOT OR OTHERWISE INTERRUPT THIS UTILITY WHILE IT IS IN PROGRESS.  DOING SO WILL RESULT IN AN UNSTABLE SYSTEM." \
	buttons {"Cancel","Continue"} default button 2 cancel button 1 with icon file "$dialogIcon"
set openingMessageChoice1 to button returned of the result
end tell
return openingMessageChoice1
EOT`
}

openingMessage2 ()
{
openingMessageChoice2=`/usr/bin/osascript << EOT
tell application "Finder"
	activate
	display alert "Before running this utility, all open applications (except Self Service and VPN) must be quit." \
	& return & return & "TIP: For best experience, leave this dialog open, shut down applications yourself, then select - Quit All Applications Now." \
	as critical buttons {"Cancel","Quit All Applications Now"} default button 2 cancel button 1
set openingMessageChoice2 to button returned of the result
end tell
return openingMessageChoice2
EOT`
}

quitAllApps ()
{
quitAllAppsStatus=`/usr/bin/osascript << EOT
set quitAllAppsStatus to "OK"
set openAppsCount to 99
repeat while openAppsCount > 0
	tell application "System Events"
		set openApps to name of every application process whose visible is true and name is not "Finder" and name is not "Self Service" and name is not "$myOrgVPN" and name is not "Terminal" and name is not "Console" and name is not "Atom"
	end tell
	set openAppsCount to count of openApps
	set AppleScript's text item delimiters to {", "} #' #Just a comment to close the single quote for Text Editing
	set displayList to openApps as string
	if openAppsCount > 0 then
		tell application "Finder"
			display dialog "The following " & openAppsCount & " application(s) need to be quit before proceeding: " & return & return & displayList & return & return & "WARNING: You may lose data if you choose to Force Quit Apps!" & return & return & "TIP: Closing windows by clicking the red dot in upper left hand corner of application does not necessarily QUIT the applicaiton.  You need to actually select QUIT from the application menu." buttons {"Cancel", "Force Quit Apps", "Check Again"} default button 3 cancel button 1 with icon caution
			set forceQuitChoice to button returned of the result
			if forceQuitChoice = "Force Quit Apps" then
				try
					repeat with closeall in openApps
						try
							do shell script "killall '" & closeall & "'"
						on error
							-- do nothing
						end try
					end repeat
					delay 2
					tell application "System Events"
						set openApps to name of every application process whose visible is true and name is not "Finder" and name is not "Self Service" and name is not "$myOrgVPN" and name is not "Terminal" and name is not "Console" and name is not "Atom"
					end tell
				end try
			end if
		end tell
	end if
end repeat
return quitAllAppsStatus
EOT`
}

suggestNewAccount ()
{
	acceptSuggestionChoice=`/usr/bin/osascript << EOT
	tell application "Finder"
		activate
		display dialog "Later, we will double-check to make sure that the following is available, but this is what we suggest for a new account:" \
			& return & return & "Long Account Name - $proposedLongName" \
			& return &  "Account Name - $proposedShortName" \
			buttons {"Customize","Accept"} default button 2
			set acceptSuggestionChoice to button returned of the result
	end tell
	return acceptSuggestionChoice
	EOT`
}

customizeLongName ()
{
	customLongName=`/usr/bin/osascript << EOT
	tell application "Finder"
		activate
		display dialog "Please enter desired Long Name for your local account:" \
			& return & return & "WARNING: Please use a unique name that only contains uppercase letters, lowercase letters, and spaces!"\
			& return & return & "Otherwise, this dialog will run over and over again until you enter an acceptable name."\
			& return & return & "If you wish to cancel this operation, type the word \"cancel\" into field below and click Continue."\
			buttons {"Continue"} default button 1 default answer "$proposedLongName"
			set customLongName to text returned of the result
	end tell
	return customLongName
	EOT`
}

longNameNotUniqueError ()
{
	/usr/bin/osascript << EOT
	tell application "Finder"
		activate
		display alert "Sorry the account name $customLongName appears to be taken already." \
		& return & return & "Please try again." \
		buttons {"OK"} default button 1
	end tell
EOT
}

checkFailDialog ()
{
customizeAfterCheckFailChoice=`/usr/bin/osascript << EOT
display dialog "Unfortunately, you can not use $effectiveLongAccountName" \
	& return & return & "$(displaySummaryDialog)" \
	& return & return & "Please select a different account name" \
	buttons {"Cancel","Customize"} default button 2 cancel button 1
set customizeAfterCheckFailChoice to button returned of the result
return customizeAfterCheckFailChoice
EOT`
}

displayFinalWarningDialog ()
{
	proceedWithConversionChoice=`/usr/bin/osascript << EOT
	display dialog "Are you certain you want to proceed with account conversion?" \
		& return & return & "New Account Name = $effectiveLongAccountName" \
		& return &  "New Account Short Name = $effectiveShortAccountName" \
		& return &  "New Home Directory = /Users/$effectiveShortAccountName" \
		& return & return & "THIS IS YOUR LAST CHANCE TO CANCEL." \
		buttons {"Cancel","Proceed"} cancel button 1
	set proceedWithConversionChoice to button returned of the result
	return proceedWithConversionChoice
EOT`
}

rebootDialog ()
{
	/usr/bin/osascript << EOT
	tell application "loginwindow"
		«event aevtrrst»
	end tell
EOT
}

#########################################
########## MAIN Functions ###############
#########################################

hideSelfService ()
{
	/usr/bin/osascript << EOT
	try
	tell application "Finder"
		set visible of process "Self Service" to false
	end tell
	end try
EOT
}

checkMobileAccount ()
{
echo -e "\n===================================\n===================================\n"
echo "Checking to see if current user is an Active Directory Mobile User account..."
if [[ `/usr/bin/dscl . -read /Users/$currentUser AuthenticationAuthority | grep  LocalCachedUser | grep "Active Directory"` ]]
	then
		echo "$currentUser is configured as an Active Directory Mobile user account"
	else
		echo "$currentUser is NOT configured as an Active Directory Mobile user account"
		echo "Aborting.."
		notMobileAccountDialog
		exit 243
fi
}

checkUserHomeDisk ()
{
	echo -e "\n===================================\n===================================\n"
	echo "Sanity Check - check if current user's home directory on same disk as /Users ?..."
	usersDirDisk=`df /Users | awk '{print $1}' | tail -1`
	currentUserDirDisk=`df "$currentUserHome" | awk '{print $1}' | tail -1`
	if [ "$usersDirDisk" == "$currentUserDirDisk" ]
		then
			echo "Sanity Check passed"
			echo "Standard Users directory resides on disk $usersDirDisk"
			echo "Current Users directory - $currentUserHome - also resides on $currentUserDirDisk"
		else
			echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!"
			echo "Sanity Check Failed !"
			echo -e "!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
			echo "Standard Users directory resides on disk $usersDirDisk"
			echo "Current Users directory - $currentUserHome - resides on $currentUserDirDisk"
			echo "Displaying explanation to user and aborting"
			diskCheckFailDialog
			exit 253
	fi
}

generateCustomizedLongName ()
{
	customizeLoop=99
	until (( $customizeLoop == 1 ))
		do
			customizeLongName
			echo "User wants to go with $customLongName for account name."
			sanitizedCustomLongName=`echo $customLongName | tr -cd '[[:alpha:][:space:]]'`
			if [ "$customLongName" == "" ]
				then
					echo "Actually - user did not enter anthing in text field.  Oops."
					customizeLongName
			elif [ "$customLongName" == "cancel" ]
				then
					echo "User Wants to Cancel"
					exit 0
			elif [ "$customLongName" == "$sanitizedCustomLongName" ]
				then
					echo "User has entered a correctly formatted Long Name"
					echo "Making sure it is not already taken..."
					if [[ `dscl . -list /Users RealName | grep "$customLongName"` ]]
						then
							echo "Well darn - this one is already taken.  Informing user to try again..."
						else
							echo "$customLongName is available"
							echo "Yee Hah - proceeding"
							effectiveLongAccountName="$customLongName"
							effectiveShortAccountName=`echo $effectiveLongAccountName | sed 's/[^a-zA-Z]//g' | tr "[:upper:]" "[:lower:]"`
							customizeLoop=1
					fi
			else
				customizeLongName
			fi
		echo -e "\n"
		done
}

proposeNewAccount ()
{
echo -e "\n===================================\n===================================\n"
echo "Here is what we know about $currentUser so far:"
echo "First Name -- $currentUserFirstName"
echo "Last Name -- $currentUserLastName"
echo "Home -- $currentUserHome"
echo "DARWIN Folder -- $currentUserDarwinFolders"
echo "UID -- $currentUserID"
echo -e "\nJust for logging purposses, let's see if $currentUser is a local admin..."
dseditgroup -o checkmember -m $currentUser -n . admin
if (( $? == 0 ))
	then
		echo "$currentUser is a local admin"
	else
		echo "$currentUser is not a local admin"
fi
proposedShortName=`echo $currentUserFirstName | sed 's/[^a-zA-Z]//g' | tr "[:upper:]" "[:lower:]"`
proposedLongName="$currentUserFirstName $currentUserLastName"
echo -e "\nFor the new account, we will propose the following --"
echo "Long Name -- $proposedLongName"
echo "Record Name -- $proposedShortName"
suggestNewAccount
if [ "$acceptSuggestionChoice" == "Accept" ]
	then
		echo "User likes what we suggested."
		effectiveLongAccountName="$proposedLongName"
		effectiveShortAccountName="$proposedShortName"
	else
		echo "User wants to customize account name."
		generateCustomizedLongName
fi
echo "The effective long name to work with will be $effectiveLongAccountName"
echo "The effective short name to work with will be $effectiveShortAccountName"
}

doubleCheckEverything ()
{
	checkScore=0
	echo -e "\nChecking to see if $effectiveShortAccountName is already an account..."
	if [ -d /Users/$effectiveShortAccountName ]
		then
			echo "Found a home directory already present at /Users/$effectiveShortAccountName"
			echo "Can not use $effectiveShortAccountName for account name"
			checksDialog[1]="FAIL - Home folder found at /Users/$effectiveShortAccountName"
			let "checkScore = $checkScore + 1"
		else
			echo "No home directory found at /Users/$effectiveShortAccountName"
			checksDialog[1]="PASS - No home directory found at /Users/$effectiveShortAccountName"
	fi
	if [[ `dscl . -list /Users RealName | grep "$effectiveLongAccountName"` ]]
		then
			echo "Found a user account with $effectiveLongAccountName"
			echo "Can not use $effectiveLongAccountName for the Long Name"
			checksDialog[2]="FAIL - Already an account with long user name $effectiveLongAccountName"
			let "checkScore = $checkScore + 1"
		else
			echo "No account with long name $effectiveLongAccountName found"
			checksDialog[2]="PASS - No account found with long user name $effectiveLongAccountName"
	fi
	if [[ `dscl . -read /Users/$effectiveShortAccountName` ]]
		then
			echo "Found a user account with $effectiveShortAccountName"
			echo "Can not use $effectiveShortAccountName"
			checksDialog[3]="Fail - Already an account with short user name $effectiveShortAccountName"
			let "checkScore = $checkScore + 1"
		else
			echo "No account with short name $effectiveShortAccountName found"
			checksDialog[3]="PASS - No account found with short user name $effectiveShortAccountName"
	fi
}

displaySummaryDialog ()
{
for checks in ${checksDialog[*]}
	do
		printf "%s\n" $checks
	done
}

unbindAD ()
{
	echo -e "\nChecking if system is bound to AD..."
	if [[ `/usr/bin/dscl localhost -list . | grep "Active Directory"` ]]
		then
			echo "System is bound to AD.  Unbinding..."
			searchPath=`/usr/bin/dscl /Search -read . CSPSearchPath | grep Active\ Directory | sed 's/^ //'`
			/usr/sbin/dsconfigad -remove -force -u none -p none
			/usr/bin/dscl /Search/Contacts -delete . CSPSearchPath "$searchPath"
			/usr/bin/dscl /Search -delete . CSPSearchPath "$searchPath"
			/usr/bin/dscl /Search -change . SearchPolicy dsAttrTypeStandard:CSPSearchPath dsAttrTypeStandard:NSPSearchPath
			/usr/bin/dscl /Search/Contacts -change . SearchPolicy dsAttrTypeStandard:CSPSearchPath dsAttrTypeStandard:NSPSearchPath
		else
			echo "System is not bound to AD."
	fi
}

backupPassword ()
{
	echo -e "\nPreserving password..."
	# Preserve the account password by backing up password hash
	shadowhash=`/usr/bin/dscl . -read /Users/$currentUser AuthenticationAuthority | grep " ;ShadowHash;HASHLIST:<"`
}

killAdAttributes ()
{
	# Remove the account attributes that identify it as an Active Directory mobile account
	echo -e "\nRemoving AD Attributes..."
	for attribute in "${attributesToKill[@]}"
		do
			if [[ `/usr/bin/dscl . -read /Users/$currentUser $attribute` ]]
				then
					echo "  Killing $attribute from local user record"
					/usr/bin/dscl . -delete /Users/$currentUser $attribute
				else
					echo "  Could not find $attribute in local user record"
			fi
		done
}

restorePassword ()
{
	echo "Restoring Password Auth Authority..."
	/usr/bin/dscl . -create /Users/$currentUser AuthenticationAuthority \'$shadowhash\'
}

finishAccountConversion ()
{
	echo -e "\nFinishing Account Conversion..."
	echo "Adding $currentUser to the staff group on this Mac..."
	/usr/sbin/dseditgroup -o edit -a "$currentUser" -t user staff
	echo "Updating Account with new dsAttrTypeNative values..."
	/usr/bin/dscl . -create /Users/$currentUser "dsAttrTypeNative:_writers_jpegphoto" "$effectiveShortAccountName"
	/usr/bin/dscl . -create /Users/$currentUser "dsAttrTypeNative:_writers_LinkedIdentity" "$effectiveShortAccountName"
	/usr/bin/dscl . -create /Users/$currentUser "dsAttrTypeNative:_writers_passwd" "$effectiveShortAccountName"
	/usr/bin/dscl . -create /Users/$currentUser "dsAttrTypeNative:_writers_picture" "$effectiveShortAccountName"
	/usr/bin/dscl . -create /Users/$currentUser "dsAttrTypeNative:_writers_realname" "$effectiveShortAccountName"
	/usr/bin/dscl . -create /Users/$currentUser "dsAttrTypeNative:_writers_hint" "$effectiveShortAccountName"
	echo "Changing Long Name and primary Group ID of current Account"
	/usr/bin/dscl . -create /Users/$currentUser RealName "$effectiveLongAccountName"
	/usr/bin/dscl . -create /Users/$currentUser PrimaryGroupID "20"
}

updatePermissions ()
{
	echo -e "\nUpdating group permissions on home directory..."
	/usr/sbin/chgrp -R staff "$currentUserHome"
	echo "Modifying home direcory name."
	mv /Users/$currentUser /Users/$effectiveShortAccountName
	echo "Killing .account file..."
	rm -f /Users/$currentUser/.account || true
}

finalizeAccount ()
{
	echo -e "\nFinalizing account settings..."
	/usr/bin/dscl . -create /Users/$currentUser NFSHomeDirectory "/Users/$effectiveShortAccountName"
	/usr/bin/dscl . -change /Users/$currentUser RecordName "$currentUser" "$effectiveShortAccountName"
	sleep 1
	/usr/bin/dscl . -append /Users/$effectiveShortAccountName RecordName "$currentUser"
}

#########################################
################ MAIN  ##################
#########################################

set_log
hideSelfService >> $log_location 2>&1
checkMobileAccount >> $log_location 2>&1
checkUserHomeDisk >> $log_location 2>&1
openingMessage1
if [ "$openingMessageChoice1" == "Continue" ]
	then quitAllApps
		if [ "$quitAllAppsStatus" != "OK" ]
			then exit 253
		fi
	else exit 253
fi
proposeNewAccount >> $log_location 2>/dev/null
doubleCheckEverything >> $log_location 2>/dev/null
if (( $checkScore > 0 ))
	then
		echo "Check Failed"  >> $log_location 2>/dev/null
		checkFailDialog
		if [ "$customizeAfterCheckFailChoice" == "Customize" ]
			then
				echo "User wants to try again." >> $log_location 2>/dev/null
				customizeTrySuccess=99
				until (( $customizeTrySuccess == 1 ))
					do
						generateCustomizedLongName >> $log_location 2>/dev/null
						doubleCheckEverything >> $log_location 2>/dev/null
						if (( $checkScore > 0 ))
							then
								echo "Apparently we still have issues." >> $log_location 2>/dev/null
								checkFailDialog
								if [ "$customizeAfterCheckFailChoice" == "Customize" ]
									then
										echo "User wants to try again" >> $log_location 2>/dev/null
									else
										echo "User wants to cancel" >> $log_location 2>/dev/null
										customizeTrySuccess=1
										exit 0
								fi
							else
								echo "We finally have something to work with." >> $log_location 2>/dev/null
								customizeTrySuccess=1
						fi
					done
			else
				echo "User wants to cancel." >> $log_location 2>/dev/null
				exit 0
		fi
	else
		echo "Check Passed"  >> $log_location 2>/dev/null
fi
echo -e "\nFor review - this is where we are headed for this conversion:"
echo "Long Name		$effectiveLongAccountName" >> $log_location 2>/dev/null
echo "Short Name		$effectiveShortAccountName" >> $log_location 2>/dev/null
echo -e "New Home Dir		/Users/$effectiveShortAccountName \n" >> $log_location 2>/dev/null
echo "Asking user if user wishes to proceed..."
displayFinalWarningDialog  >> $log_location 2>/dev/null
if [ "$proceedWithConversionChoice" == "Proceed" ]
	then
		echo "User wants to proceed" >> $log_location 2>/dev/null
	else
		echo "User wants to cancel" >> $log_location 2>/dev/null
		exit 0
fi

rm -f /tmp/hpipe
mkfifo /tmp/hpipe
$cocoaDialog progressbar --float --percent --title "Mobile to Local Account" --text "Preparing..." < /tmp/hpipe &
exec 3<> /tmp/hpipe
echo -n . >&3
echo "5 Unbinding from AD if necessary" >&3
unbindAD >> $log_location 2>/dev/null
sleep 1
echo "20 Backing up your password hash" >&3
backupPassword >> $log_location 2>/dev/null
sleep 1
echo "35 Killing Active Directory account attributes" >&3
killAdAttributes >> $log_location 2>/dev/null
sleep 1
echo "50 Restoring password hash" >&3
restorePassword >> $log_location 2>/dev/null
sleep 1
echo "65 Finishing account conversion" >&3
finishAccountConversion >> $log_location 2>/dev/null
sleep 1
echo "70 Updating group permissions on home directory" >&3
updatePermissions >> $log_location 2>/dev/null
sleep 1
echo "85 Finalizing account" >&3
finalizeAccount >> $log_location 2>/dev/null
sleep 2
exec 3>&-
wait
rm -f /tmp/hpipe

rebootDialog

exit 0
