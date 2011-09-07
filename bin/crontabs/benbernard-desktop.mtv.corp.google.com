# m h  dom mon dow   command
0 * * * * /home/benbernard/bin/backup-git.py /usr/local/google/home/benbernard /home/benbernard/git-backup
