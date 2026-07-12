#!/bin/bash

URL=http://localhost:5000/health

STATUS=$(curl -s $URL)

if [[ $STATUS != *ok* ]]; then

    systemctl restart leidsa.service

fi
