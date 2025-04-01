#!/bin/bash

# === VARIABLES ===
# Crée une variable TIMESTAMP avec la date et l'heure actuelles au format YYYYMMDD_HHMMSS.
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Définit le répertoire où les logs seront stockés.
LOG_DIR="./logs"
# Crée le chemin complet du fichier de log en utilisant le répertoire LOG_DIR et le TIMESTAMP.
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"
# Définit le répertoire où les fichiers de configuration sont stockés.
CONFIG_DIR="./config"
# Définit le chemin du fichier contenant la liste des paquets à installer.
PACKAGE_LIST="./lists/packages.txt"
USERNAME=$(logname)
USER_HOME="/home/$USERNAME"

# === FUNCTIONS ===
# Fonction pour écrire des messages dans le fichier de log avec un horodatage.
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_and_install() {
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."
  else
    log "Installing $pkg..."
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed."
    else
      log "Failed to install $pkg."
    fi
  fi
}
# Fonction pour poser une question à l'utilisateur et récupérer une réponse oui/non.
ask_yes_no() {
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}

# === INITIAL SETUP ===
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
log "Starting post-installation script. Logged user: $USERNAME"

# Vérifie si le script est exécuté en tant que root.
if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  exit 1
fi

# === 1. SYSTEM UPDATE ===
log "Updating system packages..."
apt get update && apt get upgrade -y &>>"$LOG_FILE"

# === 2. PACKAGE INSTALLATION ===
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue # Ignore les lignes vides ou commençant par # (commentaires).
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi

# === 3. UPDATE MOTD ===
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi

# === 4. CUSTOM .bashrc ===
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi

# === 5. CUSTOM .nanorc ===
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi

# === 6. ADD SSH PUBLIC KEY ===
# Demande à l'utilisateur s'il souhaite ajouter une clé SSH publique
if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi

# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi
   
log "Post-installation script completed."

exit 0