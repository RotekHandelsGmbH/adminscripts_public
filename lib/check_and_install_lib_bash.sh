check_and_install_lib_bash() {
    LIB_PATH="/usr/local/lib_bash/lib_bash.sh"

    # Define colors
    GREEN="\e[32m"
    RED="\e[31m"
    YELLOW="\e[33m"
    BLUE="\e[34m"
    RESET="\e[0m"

    # Check if lib_bash is already installed
    if [[ -f "$LIB_PATH" ]]; then
        return 0
    fi

    # Check if the script is run as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}⛔ Error: This action requires root privileges. Please run as root or with sudo.${RESET}" >&2
        exit 1
    fi

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}🔍 git is not installed. Attempting to install git...${RESET}"

        if command -v apt &> /dev/null; then
            apt update && apt install -y git || {
                echo -e "${RED}❌ Failed to install git using apt.${RESET}" >&2
                exit 1
            }
        elif command -v yum &> /dev/null; then
            yum install -y git || {
                echo -e "${RED}❌ Failed to install git using yum.${RESET}" >&2
                exit 1
            }
        else
            echo -e "${RED}🚫 No supported package manager found (apt or yum).${RESET}" >&2
            exit 1
        fi
    else
        echo -e "${GREEN}✅ git is already installed.${RESET}"
    fi

    # Clone lib_bash repository
    echo -e "${BLUE}📥 Installing lib_bash...${RESET}"
    git clone --depth 1 https://github.com/bitranox/lib_bash.git /usr/local/lib_bash || {
        echo -e "${RED}❌ Failed to clone lib_bash from GitHub.${RESET}" >&2
        exit 1
    }
    echo -e "${GREEN}🎉 lib_bash has been successfully installed!${RESET}"
}

check_and_install_lib_bash
