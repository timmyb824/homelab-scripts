#!/bin/bash

/usr/bin/rsync -av --delete /Users/timothybryant/DEV/projects/ /Volumes/filebrowser/macbook-projects/ &&
    /usr/bin/curl -m 10 --retry 5 "https://healthchecks.timmybtech.com/ping/${HC_PING_ID}"
