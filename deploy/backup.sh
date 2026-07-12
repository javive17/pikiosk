#!/bin/bash

DATE=$(date +%Y%m%d_%H%M)

DEST=$HOME/dashboard-backups

mkdir -p $DEST

tar czf \
$DEST/leidsa-dashboard-$DATE.tar.gz \
/opt/leidsa-dashboard

find $DEST -type f -mtime +15 -delete

echo Backup completed.
