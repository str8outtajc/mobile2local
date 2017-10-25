# mobile2local

Convert Active Directory Mobile Account to Local Account via Self Service

### Credits

- Rich Trouton for the "meat" of this script - [Rich's Script](https://derflounder.wordpress.com/2016/12/21/migrating-ad-mobile-accounts-to-local-user-accounts/)
- Patrick Gallagher (credited by Rich in his work) - [MigrateUserHomeToDomainAcct.sh](https://twitter.com/patgmac)
- Lisa Davies (also credited by Rich in his work)
- Kevin Hendricks - [Cocoa Dialog Progress bar example](http://mstratman.github.io/cocoadialog/examples/progressbar.sh.txt)

### This is BETA !

- Deploy as a production tool at your own risk
- It needs more testing and more feedback
- It works great in "my" organization's environment, but needs a lot more testing

### Overview

Functionally, this script pretty much does exactly what Rich's does.  

Key differences:
- Intended for use with JAMF's Self Service
- GUI dialogs for user
- Suggests a new account name for user
- Allows user to change to something custom if he or she wishes to
- Lots of error contol
  - User can't pick an existing account name
  - User can't create account name with illegal characters
  - User can't create an account if home directory for that account is already in /Users

### Known Issues and Limitations

- Unable to handle conversions if current user's home folder is not on same disk as the new home folder location.  See below

### Revision History

##### Version 1.21 Beta
- Added a check for user home directory location - it's ugly
- Determining home folder disk with variables
```shell
currentUserHome=`/usr/bin/dscl . -read /Users/$currentUser NFSHomeDirectory | sed -n 's|.* \(/.*\)|\1|p'`
currentUserDirDisk=`df "$currentUserHome" | awk '{print $1}' | tail -1`
```
- Then compare to disk for "/Users"
- If they don't match - error message - can't continue
- The idea behind all this is that new local accounts will have home directories in standard /Users.  If previous home directory was on a different disk than /Users - the rename of the home directory could potentially croak.  (not enough disk space, etc.) 


##### Version 1.22 Beta
- Fixed bug - customizeLongName function was running a second time when not necessary
