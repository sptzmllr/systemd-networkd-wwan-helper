# systemd-networkd-wwan-helper

### Deal with credentials (PIN)
To use my Sim-Cards PIN in this repo i use a git filter to delete all lines containing the comment `#gitignore` in all `.sh` files.
To use the same filter you have to define the filter in your `gitconfig`.
```
git config --local filter.gitignore.clean "sed '/#gitignore/d'"
```
```
git config --local filter.gitignore.smudge cat
```
The clean filter is `sed` with a delete pattern and the smudge is just `cat` aka do nothing.  

Test the filter on the `filter_test.sh` file!

Alternatives are removing the PIN `sudo mbimcli -d <Device> --disable-pin=<(Pin Type),(Current PIN)>`.
For the PIN Type check `sudo mbimcli -d <Device> --query-pin-list`.
The typical threat model of a notebook ist that it gets lost and since my drive is encrypted it is okay for me to store it on the drive.
An other solution ist the unlocking at start and use `mbimcli --query-pin-state` and `mbimcli --enter-pin` to check if the device is locked and ask in a prompt or a pinentry for the PIN.

