#!/bin/bash

echo "Arguments"

echo $0 #Gives the name of the script
echo $1 #For the first parameter

#For print all the parameters at once can use "$@" the quotes is to avoid re-splitting elements
echo "$@"

#To see the numbers of the parameters
echo $#

#To save a parameter
name=$1

echo "From the variable "$name