#!/bin/bash

mkdir -p tools
cd tools;

git clone https://github.com/cambridgehackers/fpgamake.git
cd fpgamake;
git pull;
cd ../;

git clone https://github.com/cambridgehackers/buildcache.git
cd buildcache;
git pull;
cd ../;

git clone git@github.com:chanwooc/connectal.git connectal
cd connectal;
git pull;
cd ../;
