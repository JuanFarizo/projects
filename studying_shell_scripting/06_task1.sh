#!/bin/bash

read -p "Which server you want to ping: " server_addr

#-c3 count for 3 | -w5 deadline 5sec

ping -c3 -w5 $server_addr
