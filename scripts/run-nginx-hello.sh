#!/bin/zsh
# Simple script to run nginx:alpine on port 80:80

docker run --rm -d --name nginx-hello -p 80:80 nginx:alpine
