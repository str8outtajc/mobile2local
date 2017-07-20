# mobile2local

Convert Active Directory Mobile Account to Local Account via Self Service

#### Credits

- Rich Trouton for the "meat" of this script - [Rich's Script](https://derflounder.wordpress.com/2016/12/21/migrating-ad-mobile-accounts-to-local-user-accounts/)
- Patrick Gallagher (credited by Rich in his work) - [MigrateUserHomeToDomainAcct.sh](https://twitter.com/patgmac)
- Lisa Davies (also credited by Rich in his work)
- Kevin Hendricks - [Cocoa Dialog Progress bar example](http://mstratman.github.io/cocoadialog/examples/progressbar.sh.txt)

#### This is BETA !

- Please do not deploy this script to prodcution environments at this time
- It needs more testing
- It works great in "my" organization's environment, but needs a lot more testing

#### Overview

Functionally, this script pretty much does exactly what Rich's does.  

Key differences:
- Intended for use with JAMF's Self Service
- GUI dialogs for user
- Suggests a new account name for user
- Allows user to change to something custom if he or she wishes to
- Lots of error contol
--* User can't pick an existing account name
--* User can't create account name with illegal characters
--* User can't create an account if home directory for that account is already in /Users

#### Known Issues and Limitations

- At this point - no account taken for user home directories that reside in custom locations
- Sometimes false positives in error control loop for account name

#### To Do

- Add stop gap to prevent tool from running if home directory is not in standard location
- Eventually - rename new home directory to same volume it is on currently 

#### Revision History

- Version 1.21 Beta
-- Added a check for user home directory location - it's ugly
-- Determining home folder disk with variables
```shell
currentUserHome=`/usr/bin/dscl . -read /Users/$currentUser NFSHomeDirectory | sed -n 's|.* \(/.*\)|\1|p'`
currentUserDirDisk=`df "$currentUserHome" | awk '{print $1}' | tail -1`
```
-- Then compare to disk for "/Users"
-- If they don't match - error message - can't continue
