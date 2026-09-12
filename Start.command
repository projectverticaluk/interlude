#!/bin/zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# The cinema script resizes the terminal and holds the Maz title while loading.
pwsh -NoLogo -NoProfile -File "${0:A:h}/run.ps1" "$@"
cinema_exit=$?
if (( cinema_exit != 0 )); then
  print "Cinema stopped with an error. Keep this launcher beside run.ps1 and make sure PowerShell is installed."
  read "?Press Return to close."
fi
exit "$cinema_exit"
