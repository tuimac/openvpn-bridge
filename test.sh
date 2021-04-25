#!/bin/bash

host dns.google | awk '{print $4}'
