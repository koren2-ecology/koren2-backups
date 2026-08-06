#!/bin/bash

source backup.sh >> "logs/$(date +%Y-%m-%d_%H-%M-%S).log" 2>&1
