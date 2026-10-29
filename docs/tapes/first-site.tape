# The guide's "first local site" in the Debian that windows-setup.tape installed, then Windows opens it.
# Played on a Windows runner by record.mjs, in .github/workflows/demos.yml, after windows-setup.tape (README.md here).
Output docs/media/first-site.gif

Set Shell "powershell"
Set FontSize 15
Set Width 1200
Set Height 720
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set WaitTimeout 120s

# Wait until the services of the restarted distribution are up.
Hide
Type "wsl -d Debian --exec systemctl is-system-running --wait; Clear-Host"
Enter
Wait /> *$/
Show

Type "wsl -d Debian --cd ~"
Sleep 300ms
Enter
Wait /\$ *$/
Sleep 1.5s

Type `mkdir -p ~/sites/shop/public && echo '<?php echo "PHP ", PHP_VERSION, PHP_EOL;' > ~/sites/shop/public/index.php`
Sleep 300ms
Enter
Wait /\$ *$/
Type "cd ~/sites/shop"
Enter
Wait /\$ *$/
Type "gash hte site create --domain shop.test --docroot public --php 8.4"
Sleep 300ms
Enter
Wait /\$ *$/
Sleep 3s
Type "curl -k https://shop.test/"
Sleep 300ms
Enter
Wait /\$ *$/
Sleep 2.5s
Type "gash hte hosts windows"
Sleep 300ms
Enter
Wait /\$ *$/
Sleep 3s
Type "exit"
Enter
Wait /> *$/

# Back in Windows: the hosts line, as Administrator, then Windows opens the site.
Type "Add-Content $env:WINDIR\System32\drivers\etc\hosts '127.0.0.1 shop.test'"
Sleep 300ms
Enter
Wait /> *$/
Type "curl.exe -k https://shop.test/"
Sleep 300ms
Enter
Wait /> *$/
Sleep 5s
