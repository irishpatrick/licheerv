#!/bin/bash

source ./config/buildcfg
docker build -t licheerv --build-arg CFGUSERNAME=$CFGUSERNAME --build-arg CFGUSERHASH=$CFGUSERHASH .
