#!/usr/bin/env bash
set -euo pipefail

# Safer updater for the local pvenode repository.
# By default this is interactive and will not discard local changes without confirmation.

REPO_DIR="/usr/local/sbin/pvenode"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

usage() {
	cat <<EOF
Usage: $(basename "$0") [-f|--force]

Options:
  -f, --force    Non-interactive: perform a hard reset to origin/main (dangerous)
  -h, --help     Show this help

This script updates the repository at ${REPO_DIR}. It will fetch and try to
update safely. Without --force it will prompt before discarding local work.
EOF
}

FORCE=0
while [[ ${#} -gt 0 ]]; do
	case "$1" in
		-f|--force) FORCE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		--) shift; break ;;
		-*) echo "Unknown option: $1"; usage; exit 2 ;;
		*) break ;;
	esac
done

cd "$REPO_DIR" || { echo -e "${RED}Repository directory not found: ${REPO_DIR}${RESET}"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo -e "${RED}Not a git repository: ${REPO_DIR}${RESET}";
	exit 1
fi

echo -e "${YELLOW}Fetching all branches...${RESET}"
git fetch --all --prune

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
UPSTREAM_REF="origin/main"

prompt_yes_no() {
	local prompt="$1" default=${2:-n}
	local reply
	read -rp "$prompt" reply
	reply=${reply:-$default}
	case "$reply" in
		[Yy]*) return 0 ;;
		*) return 1 ;;
	esac
}

STATUS=$(git status --porcelain)
if [[ -n "$STATUS" ]]; then
	echo -e "${YELLOW}Uncommitted changes detected:${RESET}"
	git --no-pager status --short

	if [[ $FORCE -eq 1 ]]; then
		echo -e "${RED}Warning: --force provided; proceeding will discard uncommitted changes.${RESET}"
		if ! prompt_yes_no "Really discard uncommitted changes and continue? (y/N): " n; then
			echo "Aborted."; exit 1
		fi
	else
		echo "Options:"
		echo "  s) Stash changes and attempt a safe pull (recommended)"
		echo "  b) Create a backup branch from changes (safe)"
		echo "  a) Abort"
		read -rp "Choose an option [s/b/a] (default s): " opt
		opt=${opt:-s}
		if [[ "$opt" == "s" ]]; then
			echo "Stashing changes..."
			git stash push -u -m "autostash before update $(date -Iseconds)" >/dev/null
		elif [[ "$opt" == "b" ]]; then
			TS=$(date +%Y%m%d-%H%M%S)
			BACKUP_BRANCH="backup/${TS}"
			echo "Creating backup branch ${BACKUP_BRANCH} from current state..."
			git stash push -u -m "backup before update ${TS}" >/dev/null
			if git stash list | grep -q "backup before update ${TS}"; then
				git stash branch "${BACKUP_BRANCH}" >/dev/null || true
				echo "Saved local changes on branch ${BACKUP_BRANCH}."
			else
				echo "Failed to create stash/backup; aborting."; exit 1
			fi
		else
			echo "Aborted by user."; exit 1
		fi
	fi
fi

LOCAL_HASH=$(git rev-parse @)
REMOTE_HASH=$(git rev-parse "$UPSTREAM_REF" 2>/dev/null || true)
BASE_HASH=$(git merge-base @ "$UPSTREAM_REF" 2>/dev/null || true)

if [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
	echo -e "${GREEN}Already up-to-date with ${UPSTREAM_REF}.${RESET}"
elif [[ "$LOCAL_HASH" == "$BASE_HASH" ]]; then
	echo -e "${YELLOW}Local is behind ${UPSTREAM_REF}; attempting fast-forward merge...${RESET}"
	if git pull --ff-only; then
		echo -e "${GREEN}Fast-forwarded successfully.${RESET}"
	else
		echo -e "${RED}Fast-forward failed. You may need to merge manually or use --force.${RESET}"
		exit 1
	fi
elif [[ "$REMOTE_HASH" == "$BASE_HASH" ]]; then
	echo -e "${YELLOW}Local has commits that are not on ${UPSTREAM_REF}.${RESET}"
	if [[ $FORCE -eq 1 ]]; then
		echo -e "${RED}--force given: performing hard reset to ${UPSTREAM_REF}.${RESET}"
		git reset --hard "$UPSTREAM_REF"
	else
		if prompt_yes_no "Reset local branch to ${UPSTREAM_REF} (this will discard local commits)? (y/N): " n; then
			git reset --hard "$UPSTREAM_REF"
		else
			echo "Aborted to preserve local commits. Consider creating a backup branch and pushing it."; exit 1
		fi
	fi
else
	echo -e "${RED}Local and remote have diverged.${RESET}"
	if [[ $FORCE -eq 1 ]]; then
		echo -e "${RED}--force given: performing hard reset to ${UPSTREAM_REF}.${RESET}"
		git reset --hard "$UPSTREAM_REF"
	else
		if prompt_yes_no "Perform hard reset to ${UPSTREAM_REF} and discard local changes/commits? (y/N): " n; then
			git reset --hard "$UPSTREAM_REF"
		else
			echo "Aborted. Resolve divergence manually."; exit 1
		fi
	fi
fi

echo -e "${GREEN}Setting executable permissions for scripts...${RESET}"
for f in lxc.sh pull.sh 00-motd rm_beszel.sh; do
	if [[ -f "$f" ]]; then
		chmod +x "$f"
		echo -e "  ${f} is now executable."
	fi
done

REPO_MOTD="00-motd"
TARGET_DIR="/etc/update-motd.d"
TARGET_MOTD="${TARGET_DIR}/00-motd"

if [[ -f "${REPO_MOTD}" ]]; then
	deploy_needed=0
	if [[ -f "${TARGET_MOTD}" ]]; then
		if ! cmp -s "${REPO_MOTD}" "${TARGET_MOTD}"; then
			deploy_needed=1
		fi
	else
		deploy_needed=1
	fi

	if [[ $deploy_needed -eq 1 ]]; then
		echo -e "${YELLOW}Deploying updated 00-motd to ${TARGET_MOTD}${RESET}"

		if [[ $(id -u) -eq 0 ]]; then
			mkdir -p "${TARGET_DIR}" >/dev/null 2>&1 || true
			cp "${REPO_MOTD}" "${TARGET_MOTD}"
			chmod +x "${TARGET_MOTD}"
			echo -e "${GREEN}Installed ${TARGET_MOTD}${RESET}"
		else
			if command -v sudo >/dev/null 2>&1; then
				sudo mkdir -p "${TARGET_DIR}" >/dev/null 2>&1 || true
				if sudo cp "${REPO_MOTD}" "${TARGET_MOTD}"; then
					sudo chmod +x "${TARGET_MOTD}"
					echo -e "${GREEN}Installed ${TARGET_MOTD} (via sudo)${RESET}"
				else
					echo -e "${RED}Failed to copy ${REPO_MOTD} to ${TARGET_MOTD} using sudo.${RESET}"
				fi
			else
				echo -e "${RED}Need root privileges to install ${TARGET_MOTD}. Run as root or install sudo.${RESET}"
			fi
		fi
	else
		echo -e "${GREEN}${TARGET_MOTD} is up-to-date.${RESET}"
	fi
fi

echo -e "${GREEN}Done!${RESET}"
