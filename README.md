# systemd-networkd-wwan-helper

### Deal with credentials (PIN)
To use my Sim-Cards PIN in this repo i use a git filter to delete all lines containing the comment `#gitignore` in all `.sh` files.
To use the same filter you have to define the filter in your `gitconfig`
```
git config --local filter.gitignore.clean "sed '/#gitignore/d'"
```
```
git config --local filter.gitignore.smudge cat
```
The clean filter is `sed` with a delete pattern and the smudge is just `cat` aka do nothing.  

Test the filter on the `filter_test.sh` file!

