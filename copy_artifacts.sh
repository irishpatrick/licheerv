#!/bin/bash

id=$(docker create licheerv)
docker cp $id:/output $(pwd)
docker rm -v $id
chown $SUDO_USER output -R
chmod 775 output -R
