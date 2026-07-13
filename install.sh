#!/bin/sh

set -eu

REPO_URL="https://github.com/Gakuseei/rishot.git"
PREFIX="${HOME}/.local/share/rishot"
BINDIR="${HOME}/.local/bin"

say() { printf '%s\n' "$*"; }
warn() { printf 'rishot: %s\n' "$*" >&2; }
die() {
  printf 'rishot: %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

is_atomic() { [ -f /run/ostree-booted ]; }

de_is_kde() {
  printf '%s' "${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}" |
    grep -iqE 'kde|plasma' ||
    [ -n "${KDE_FULL_SESSION:-}${KDE_SESSION_VERSION:-}" ]
}

detect_pm() {
  if have yay; then
    echo yay
  elif have paru; then
    echo paru
  elif have pacman; then
    echo pacman
  elif have apt-get; then
    echo apt
  elif have dnf; then
    echo dnf
  elif have zypper; then
    echo zypper
  elif have xbps-install; then
    echo xbps
  elif have nix-env; then
    echo nix
  else
    echo unknown
  fi
}

print_manual_deps() {
  say "Install these yourself, then re-run:"
  say "  required: quickshell, wl-clipboard, qt6-declarative, qt6-svg, qt6-5compat, qt6-wayland"
  say "  optional: imagemagick, cliphist, curl, kdialog, libnotify"
  say "  on KDE/KWin: spectacle (rishot captures through it; KWin has no screencopy protocol)"
  say "quickshell lives in: Arch extra, Debian/Ubuntu, Fedora COPR errornointernet/quickshell, NixOS, Void."
}

print_atomic_deps() {
  say "Checking what is already here:"
  for c in qs wl-copy; do
    if have "$c"; then say "  $c: present"; else say "  $c: MISSING (required)"; fi
  done
  if de_is_kde; then
    if have spectacle; then say "  spectacle: present"; else say "  spectacle: MISSING (KDE capture)"; fi
  fi
  for c in magick cliphist curl kdialog notify-send; do
    if have "$c"; then say "  $c: present"; else say "  $c: missing (optional)"; fi
  done
  if ! have qs || { de_is_kde && ! have spectacle; }; then
    say ""
    say "Missing pieces need a system install. On an atomic system pick one:"
    say "  distrobox: run rishot from an Arch or Fedora box that has the packages"
    say "  layered:   rpm-ostree install quickshell spectacle   (needs a reboot)"
    say "             quickshell COPR (if needed): https://copr.fedorainfracloud.org/coprs/errornointernet/quickshell/"
    say "After a layered install, reboot, then re-run this script."
  fi
}

install_kde_capture() {
  pm="$1"
  case "$pm" in
  apt) pkg=kde-spectacle ;;
  nix)
    warn "KDE detected: add 'kdePackages.spectacle' to your Nix env so rishot can capture"
    return 0
    ;;
  unknown)
    warn "KDE detected: install 'spectacle' yourself; rishot captures through it on KWin"
    return 0
    ;;
  *) pkg=spectacle ;;
  esac
  say "KDE detected: installing spectacle (rishot captures through it on KWin)…"
  opt_install "$pm" "$pkg"
  have spectacle || warn "spectacle is still missing; rishot cannot capture on KDE until it is installed"
}

opt_install() {
  pm="$1"
  pkg="$2"
  case "$pm" in
  yay | paru) "$pm" -S --needed --noconfirm "$pkg" >/dev/null 2>&1 ;;
  pacman) sudo pacman -S --needed --noconfirm "$pkg" >/dev/null 2>&1 ;;
  apt) sudo apt-get install -y "$pkg" >/dev/null 2>&1 ;;
  dnf) sudo dnf install -y "$pkg" >/dev/null 2>&1 ;;
  zypper) sudo zypper install -y "$pkg" >/dev/null 2>&1 ;;
  xbps) sudo xbps-install -Sy "$pkg" >/dev/null 2>&1 ;;
  *) return 0 ;;
  esac || warn "optional dep '$pkg' unavailable in your repos, skipping (one rishot feature stays off)"
}

install_optionals() {
  pm="$1"
  shift
  say "Installing optional deps (save dialog, clip history, upload, multi-monitor stitch)…"
  for pkg in "$@"; do opt_install "$pm" "$pkg"; done
}

install_deps() {
  pm="$1"
  case "$pm" in
  yay | paru)
    say "Installing deps via $pm (quickshell from extra or AUR)…"
    "$pm" -S --needed --noconfirm quickshell wl-clipboard \
      qt6-declarative qt6-svg qt6-5compat qt6-wayland || return 1
    install_optionals "$pm" imagemagick cliphist curl kdialog libnotify
    ;;
  pacman)
    say "Installing deps via pacman…"
    sudo pacman -S --needed --noconfirm wl-clipboard \
      qt6-declarative qt6-svg qt6-5compat qt6-wayland ||
      warn "some pacman deps failed"
    if ! have qs; then
      sudo pacman -S --needed --noconfirm quickshell 2>/dev/null || {
        warn "quickshell not in your repos; try an AUR helper (yay/paru) for 'quickshell'"
        return 1
      }
    fi
    install_optionals pacman imagemagick cliphist curl kdialog libnotify
    ;;
  apt)
    say "Installing deps via apt…"
    sudo apt-get update || true
    sudo apt-get install -y quickshell wl-clipboard \
      libqt6svg6 qt6-wayland || return 1
    install_optionals apt imagemagick cliphist curl kdialog libnotify-bin
    ;;
  dnf)
    say "Installing deps via dnf…"
    sudo dnf install -y wl-clipboard \
      qt6-qtdeclarative qt6-qtsvg qt6-qt5compat qt6-qtwayland ||
      warn "some dnf deps failed"
    if ! sudo dnf install -y quickshell; then
      if [ "${RISHOT_ENABLE_COPR:-0}" = 1 ]; then
        warn "enabling third-party COPR errornointernet/quickshell (RISHOT_ENABLE_COPR=1)"
        if sudo dnf -y copr enable errornointernet/quickshell && sudo dnf install -y quickshell; then
          :
        else
          warn "COPR install failed; check the COPR build vs your Qt6 version"
          return 1
        fi
      else
        warn "quickshell is not in your Fedora repos. The community COPR has it:"
        say "  sudo dnf copr enable errornointernet/quickshell"
        say "  sudo dnf install quickshell"
        say "or re-run this installer with RISHOT_ENABLE_COPR=1 to add it for you"
        return 1
      fi
    fi
    install_optionals dnf ImageMagick cliphist curl kdialog libnotify
    ;;
  zypper)
    say "Installing deps via zypper…"
    sudo zypper install -y wl-clipboard \
      qt6-declarative qt6-svg qt6-qt5compat qt6-wayland ||
      warn "some zypper deps failed"
    sudo zypper install -y quickshell || {
      warn "quickshell is not in base openSUSE repos; add an OBS repo first"
      warn "(e.g. home:AvengeMedia:danklinux), then install 'quickshell'"
      return 1
    }
    install_optionals zypper ImageMagick cliphist curl kdialog libnotify-tools
    ;;
  xbps)
    say "Installing deps via xbps…"
    sudo xbps-install -Sy quickshell wl-clipboard \
      qt6-declarative qt6-svg qt6-qt5compat qt6-wayland || return 1
    install_optionals xbps ImageMagick cliphist curl kdialog libnotify
    ;;
  nix)
    warn "Nix detected. This installer will not mutate a Nix system."
    say "Add 'quickshell' and 'wl-clipboard' to your environment, e.g.:"
    say "  nix-shell -p quickshell wl-clipboard qt6.qtdeclarative"
    say "or add them to your home-manager / configuration.nix."
    return 1
    ;;
  *)
    warn "unknown package manager; skipping automatic dep install"
    print_manual_deps
    return 1
    ;;
  esac
}

install_files() {
  mkdir -p "$PREFIX" "$BINDIR"

  self_dir=""
  if [ -n "${0:-}" ] && [ -f "$0" ]; then
    self_dir=$(unset CDPATH && cd -- "$(dirname -- "$0")" && pwd)
  fi

  if [ -n "$self_dir" ] && [ -f "$self_dir/install.sh" ] && [ -d "$self_dir/src" ] && [ -f "$self_dir/bin/rishot" ]; then
    say "Installing from checkout: $self_dir"
    rm -rf "${PREFIX:?}/src" "${PREFIX:?}/bin"
    cp -R "$self_dir/src" "$PREFIX/src"
    cp -R "$self_dir/bin" "$PREFIX/bin"
  else
    if ! have git; then die "git is required to fetch rishot (or run install.sh from a checkout)"; fi
    say "Fetching rishot into $PREFIX …"
    if [ -d "$PREFIX/.git" ]; then
      git -C "$PREFIX" pull --ff-only || {
        warn "update pull failed; re-cloning a fresh copy"
        rm -rf "${PREFIX:?}"
        git clone --depth 1 "$REPO_URL" "$PREFIX"
      }
    else
      rm -rf "${PREFIX:?}"
      git clone --depth 1 "$REPO_URL" "$PREFIX"
    fi
  fi

  [ -f "$PREFIX/src/shell.qml" ] || die "install looks wrong: $PREFIX/src/shell.qml missing"
  chmod 755 "$PREFIX/bin/rishot"
  ln -sf "$PREFIX/bin/rishot" "$BINDIR/rishot"

  datadir="${XDG_DATA_HOME:-$HOME/.local/share}"
  icon_src=""
  if [ -n "$self_dir" ] && [ -f "$self_dir/packaging/rishot.svg" ]; then
    icon_src="$self_dir/packaging/rishot.svg"
  elif [ -f "$PREFIX/packaging/rishot.svg" ]; then
    icon_src="$PREFIX/packaging/rishot.svg"
  fi
  if [ -n "$icon_src" ]; then
    mkdir -p "$datadir/icons/hicolor/scalable/apps"
    cp "$icon_src" "$datadir/icons/hicolor/scalable/apps/rishot.svg"
  fi
  desk_src=""
  if [ -n "$self_dir" ] && [ -f "$self_dir/rishot.desktop" ]; then
    desk_src="$self_dir/rishot.desktop"
  elif [ -f "$PREFIX/rishot.desktop" ]; then
    desk_src="$PREFIX/rishot.desktop"
  fi
  if [ -n "$desk_src" ]; then
    mkdir -p "$datadir/applications"
    cp "$desk_src" "$datadir/applications/rishot.desktop"
  fi
}

check_path() {
  case ":${PATH}:" in
  *":${BINDIR}:"*) ;;
  *)
    warn "$BINDIR is not on your PATH; add it, e.g. in ~/.profile:"
    say '  export PATH="$HOME/.local/bin:$PATH"'
    ;;
  esac
}

print_keybind() {
  case ":${PATH}:" in
  *":${BINDIR}:"*) cmd="rishot" ;;
  *) cmd="$BINDIR/rishot" ;;
  esac
  say ""
  say "Bind it to a key in your compositor config (it has no global hotkey):"
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    say "  Hyprland (conf):  bind = , Print, exec, $cmd"
    say "  Hyprland (lua):   hl.bind(\"Print\", hl.dsp.exec_cmd(\"$cmd\"))"
  elif [ -n "${SWAYSOCK:-}" ]; then
    say "  Sway:             bindsym Print exec $cmd"
  elif [ -n "${NIRI_SOCKET:-}" ]; then
    say "  Niri:             bind it to '$cmd' in your niri keybinds"
  else
    say "  Hyprland (conf):  bind = , Print, exec, $cmd"
    say "  Hyprland (lua):   hl.bind(\"Print\", hl.dsp.exec_cmd(\"$cmd\"))"
    say "  Sway:             bindsym Print exec $cmd"
  fi
}

main() {
  say "rishot installer"
  say ""

  if is_atomic; then
    say "Atomic system detected (rpm-ostree); dnf cannot install here, skipping it."
    print_atomic_deps
  else
    pm=$(detect_pm)
    say "Package manager: $pm"
    if ! install_deps "$pm"; then
      warn "dependencies need manual attention (see above); continuing with the file install"
    fi
    if de_is_kde; then install_kde_capture "$pm"; fi
  fi

  install_files
  check_path

  if ! have qs; then
    warn "'qs' (quickshell) is not on PATH yet; rishot needs it to run"
    is_atomic || print_manual_deps
  fi

  print_keybind

  say ""
  say "Done. Installed to $PREFIX, launcher at $BINDIR/rishot."
  say "Run it with:  rishot          (region / window)"
  say "         or:  rishot monitor  (whole output)"
}

main "$@"

