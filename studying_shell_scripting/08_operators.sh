#!/bin/bash

read -p "Enter n1 " n1
read -p "Enter n2 " n2

echo "Addition " $((n1+n2))

echo "Substraction " $((n1-n2))

echo "Mulit " $((n1*n2))

echo "Div " $((n1/n2))

echo "Mod " $((n1%n2))

echo "Pow " $((n1**n2))

echo "Increment " $((++n1))

echo "Decrement " $((--n1))

#Relational Operator

if [ $n1 -gt $n2 ] #gt ge le ls   -a for and -o for or
then 
    echo "n1 is greater"
fi