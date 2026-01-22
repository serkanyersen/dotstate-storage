#!/bin/bash

sudo add-apt-repository -y ppa:neovim-ppa/unstable
sudo apt -y update
sudo apt -y upgrade neovim
touch ~/.install-done
