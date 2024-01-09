#!/bin/bash

read -p "User name: " user_name
read -p "Enter ip: " IP

ssh $user_name@$IP

