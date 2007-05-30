#!/usr/bin/env bash

# One GiB of zeros should be enough
dd if=/dev/zero of=../support/1GiBzeros bs=1073741824 count=1
