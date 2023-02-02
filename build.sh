#!/usr/bin/env bash

ikiwiki --setup ./ikiwiki.setup

# HACK to get around autoindex fucking up the tag cloud
mv ./www/Discover_Cloud/index.html ./www/Discover/
sed -i 's/Discover Cloud/Discover/g' ./www/Discover/index.html
