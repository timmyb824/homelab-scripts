#!/bin/bash
sudo setfacl -m g:alloy:rx /var/log/crowdsec.log
sudo setfacl -m g:alloy:rx /var/log/crowdsec_api.log
sudo setfacl -m g:alloy:rx /var/log/crowdsec-firewall-bouncer.log
sudo systemctl restart alloy
