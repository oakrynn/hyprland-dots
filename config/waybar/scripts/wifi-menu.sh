#!/usr/bin/env bash

# Interactive Wi-Fi menu for Polybar click.
# Dependencies: nmcli, rofi, notify-send (optional)

set -e

# Helper: show top-level menu
show_main_menu() {
    # Refresh scan in background so list is reasonably current
    nmcli device wifi rescan >/dev/null 2>&1

    radio=$(nmcli -t -f WIFI g)
    active_ssid=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')
    status_line="Wi-Fi: ${radio^^}"
    if [[ -n "$active_ssid" ]]; then
        status_line+=" | Connected: $active_ssid"
    else
        status_line+=" | Disconnected"
    fi

    # Build list: toggle, rescan, current connection block, available networks
    menu_items=()
    menu_items+=("Toggle Wi-Fi ($radio)")
    menu_items+=("Rescan networks")
    menu_items+=("---")
    if [[ -n "$active_ssid" ]]; then
        menu_items+=("Current: $active_ssid")
    fi
    # List available SSIDs with signal and security, mark active
    mapfile -t wifi_list < <(nmcli -f IN-USE,SSID,SIGNAL,SECURITY -t dev wifi | sort -t: -k3 -rn)
    for line in "${wifi_list[@]}"; do
        IFS=":" read -r inuse ssid signal sec <<< "$line"
        [[ -z "$ssid" ]] && continue
        prefix="  "
        if [[ "$inuse" == "*" ]]; then
            prefix="* "
        fi
        menu_items+=("$prefix$ssid | ${signal}% | $sec")
    done
    menu_items+=("---")
    menu_items+=("Quit")

    choice=$(printf '%s\n' "${menu_items[@]}" | rofi -dmenu -i -p "$status_line" -format s)

    [[ -z "$choice" ]] && exit

    case "$choice" in
        Toggle\ Wi-Fi*)
            if [[ "$radio" == "enabled" ]]; then
                nmcli radio wifi off
                notify-send "Wi-Fi" "Disabled"
            else
                nmcli radio wifi on
                notify-send "Wi-Fi" "Enabled"
            fi
            ;;
        Rescan\ networks)
            nmcli device wifi rescan
            ;;
        "Current:"*)
            # Manage current connection
            handle_network_action "$active_ssid"
            ;;
        \**)
            # Active network selected
            # Strip leading "* "
            ssid=${choice#\* }
            ssid=${ssid%%|*}
            ssid="${ssid%% }"
            handle_network_action "$ssid"
            ;;
        "  "*)
            # Non-active network chosen
            ssid=${choice#  }
            ssid=${ssid%%|*}
            ssid="${ssid%% }"
            handle_network_action "$ssid"
            ;;
        Quit)
            exit 0
            ;;
    esac
}

# Submenu for a given SSID
handle_network_action() {
    ssid="$1"
    # Determine if connected
    current=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')
    actions=()
    if [[ "$ssid" == "$current" ]]; then
        actions+=("Disconnect")
        actions+=("Show password")
        actions+=("Forget network")
    else
        actions+=("Connect")
        actions+=("Show password (if saved)")
        actions+=("Forget network")
    fi
    actions+=("Back")

    choice=$(printf '%s\n' "${actions[@]}" | rofi -dmenu -i -p "$ssid" -format s)
    [[ -z "$choice" ]] && return

    case "$choice" in
        Connect)
            # Try auto-connect; if secured ask for password
            sec=$(nmcli -t -f SECURITY dev wifi | grep -F "$ssid" || true)
            if nmcli connection show "$ssid" &>/dev/null; then
                nmcli connection up "$ssid"
            else
                # Prompt for password if necessary
                # Check if open:
                info=$(nmcli -f SSID,SECURITY -t dev wifi | grep "^$ssid:" || true)
                security=${info#*:}
                if [[ "$security" != "--" && -n "$security" ]]; then
                    pass=$(printf "" | rofi -dmenu -p "Password for $ssid:" -password)
                    [[ -z "$pass" ]] && return
                    nmcli device wifi connect "$ssid" password "$pass"
                else
                    nmcli device wifi connect "$ssid"
                fi
            fi
            ;;
        Disconnect)
            nmcli connection down "$ssid"
            ;;
        "Show password"*)
            # requires privileges on some setups; try to show stored secret
            secret=$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null || \
                     nmcli -s -g password connection show "$ssid" 2>/dev/null)
            if [[ -n "$secret" ]]; then
                printf '%s\n' "$secret" | rofi -dmenu -p "Password for $ssid:" -mesg "Stored password"
            else
                notify-send "Wi-Fi" "No saved password or insufficient permission to show it"
            fi
            ;;
        "Forget network")
            nmcli connection delete "$ssid"
            ;;
        Back)
            show_main_menu
            ;;
    esac
}

# Entrypoint
show_main_menu
