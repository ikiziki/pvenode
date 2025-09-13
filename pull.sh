#!/usr/bin/env bash

# Color codes
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo -e "${YELLOW}Fetching all branches...${RESET}"
git fetch --all

echo -e "${YELLOW}Resetting local branch to match origin...${RESET}"
git reset --hard origin

echo -e "${GREEN}Setting executable permissions for scripts...${RESET}"
chmod +x lxc.sh
echo -e "${GREEN}  lxc.sh is now executable.${RESET}"
chmod +x pull.sh
echo -e "${GREEN}  pull.sh is now executable.${RESET}"

echo -e "${GREEN}Done!${RESET}"