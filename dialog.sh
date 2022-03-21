#!/bin/sh

UID=-1

trap Interrupt SIGINT

Entrance() {
    selection=$(dialog \
        --title "Entrance" \
        --cancel-label "Exit" \
        --clear \
        --stdout \
        --menu "Please select the command you want to use" 20 60 15 \
        1 "POST ANNOUNCEMENT" \
        2 "USER LIST")

    local result=$?
    case $result in
        0)
            case $selection in
                1) Announcement_list;;
                2) Users_list;;
            esac
            ;;
        1) Exit;;
        255) Esc;;
    esac
}

Announcement_list() {
    local option=$(getent passwd \
        | grep -v 'sbin/nologin\|#' \
        | sort -t: -k3 -n \
        | awk -F: '{print $3 " " $1 " OFF"}')

    selection=$(dialog \
        --title "Post announcement" \
        --extra-button \
        --extra-label "All" \
        --clear \
        --stdout \
        --checklist "Please choose who you want to post" 20 60 15 \
        $option)

    local result=$?
    case $result in
        0) Announcement_post "$selection";;
        1) Entrance;;
        3)
            local allusr=$(getent passwd \
                | grep -v 'sbin/nologin\|#' \
                | awk -F: '{print $3}' \
                | uniq \
                | xargs echo)
            
            Announcement_post "$allusr"
            ;;
        255) Esc;;
    esac
}

Announcement_post() {
    local postto=$1
    if [ "$postto" = "" ]; then
        Error_msg 1 "please select at least one user to post your announcement"
    fi

    message=$(dialog \
        --title "Post announcement" \
        --clear \
        --stdout \
        --inputbox "Enter your messages:" 20 60)

    local result=$?
    case $result in
        0)
            for var in $postto; do
                local uname=$(id -nu $var)
                echo "$message" | write $uname 2> /dev/null
            done
            Entrance
            ;;
        1) Entrance;;
        255) Esc;;
    esac
}

Users_list() {
    local option=$(getent passwd \
        | grep -v 'sbin/nologin\|#' \
        | sort -t: -k3 -n \
        | awk -F: '{ \
            if (system("who | grep "$1" > /dev/null") == 0) print $3 " " $1 "[*]"; \
            else print $3 " " $1}')

    selection=$(dialog \
        --title "Users" \
        --ok-label "Select" \
        --clear \
        --stdout \
        --menu "User info" 20 60 15 \
        $option)

    local result=$?
    case $result in
        0)
            UID=$selection
            Users_action
            ;;
        1) Entrance;;
        255) Esc;;
    esac
}

Users_action() {
    local uname=$(id -nu $UID)
    local option1=""

    if [ `whoami` = "root" ]; then
        local locked=$(grep "$uname" /etc/master.passwd | grep *LOCKED*)
        if [ "$locked" = "" ];  then
            option1="LOCK IT"
        else
            option1="UNLOCK IT"
        fi
    else
        option1="YOU MUST BE ROOT TO LOCK/UNLOCK IT"
    fi

    selection=$(dialog \
        --title "Users" \
        --ok-label "Select" \
        --clear \
        --stdout \
        --colors \
        --menu "\Z6User $uname" 20 60 15 \
        1 "$option1" \
        2 "GROUP INFO" \
        3 "PORT INFO" \
        4 "LOGIN HISTORY" \
        5 "SUDO LOG")

    local result=$?
    case $result in
        0)
            case $selection in
                1) 
                    if [ "$option1" = "YOU MUST BE ROOT TO LOCK/UNLOCK IT" ]; then
                        Users_action
                    else
                        Users_lock "$option1"
                    fi
                    ;;
                2) Users_group;;
                3) Users_port;;
                4) Users_history;;
                5) Users_log;;
            esac
            ;;
        1) Users_list;;
        255) Esc;;
    esac
}

Users_lock() {
    local msg=$1

    dialog \
        --title "$msg" \
        --clear \
        --colors \
        --yesno "\Z5Are you sure you want to do this?" 20 60

    local result=$?
    case $result in
        0) Users_lock_success "$msg";;
        1) Users_action;;
        255) Esc;;
    esac
}

Users_lock_success() {
    local msg1=$1
    local msg2=""
    local uname=$(id -nu $UID)

    if [ "$msg1" = "LOCK IT" ]; then
        pw lock $uname
        msg2="LOCK SUCCEED!"
    elif [ "$msg1" = "UNLOCK IT" ]; then
        pw unlock $uname
        msg2="UNLOCK SUCCEED!"
    else
        Exit
    fi

    dialog \
        --title "$msg1" \
        --clear \
        --colors \
        --msgbox "\Z3$msg2" 20 60

    local result=$?
    case $result in
        0) Users_action;;
        255) Esc;;
    esac
}

Users_group() {
    local msg1="GROUP_ID\tGROUP_NAME"
    local msg2="GROUP_ID GROUP_NAME"
    local uname=$(id -nu $UID)
    local gnames=$(groups $uname | xargs -n1)
    local info=$(getent group \
        | grep "$gnames" \
        | sort -t: -k3 -n \
        | awk -F: '{print $3 "\t\t" $1}')

    dialog \
        --title "Group" \
        --clear \
        --yes-label "OK" \
        --no-label "Export" \
        --cr-wrap \
        --no-collapse \
        --yesno "$msg2\n$info" 20 60

    local result=$?
    case $result in
        0) Users_action;;
        1) Export 1 "$msg1" "$info";;
        255) Esc;;
    esac
}

Users_port() {
    local uname=$(id -nu $UID)
    local ports=$(sockstat -4 \
        | grep "^$uname" \
        | awk '{print $3 " " $5 "_" $6}')
    
    if [ "$ports" = "" ]; then
        Error_msg 2 "the user has no record of listening ports"
    fi
    
    selection=$(dialog \
        --title "Port info (PID and Port)" \
        --ok-label "Select" \
        --clear \
        --stdout \
        --scrollbar \
        --menu "Select one to see more details" 20 60 15 \
        $ports)

    local result=$?
    case $result in
        0) Users_port_detail "$selection";;
        1) Users_action;;
        255) Esc;;
    esac
}

Users_port_detail() {
    local pid=$1
    local uname=$(id -nu $UID)
    local msg="USER     ${uname}"
    local info=$(ps -A -eo pid,ppid,stat,%cpu,%mem,comm -p "$pid" | rs -T)
    
    dialog \
        --title "Port info (PID and Port)" \
        --clear \
        --yes-label "OK" \
        --no-label "Export" \
        --cr-wrap \
        --no-collapse \
        --scrollbar \
        --yesno "$msg\n$info" 20 60

    local result=$?
    case $result in
        0) Users_port;;
        1) Export 2 "$msg" "$info" "$pid";;
        255) Esc;;
    esac
}

Users_history() {
    local uname=$(id -nu $UID)
    local msg1="DATE\t\t\tIP"
    local msg2="DATE IP"
    local info=$(last \
        | grep ".\..\..\.." \
        | grep "$uname" \
        | awk '{print $4, $5, $6, $7 "\t\t" $3}' \
        | head -n 10)

    dialog \
        --title "Login history" \
        --clear \
        --yes-label "OK" \
        --no-label "Export" \
        --cr-wrap \
        --no-collapse \
        --yesno "$msg2\n$info" 20 60

    local result=$?
    case $result in
        0) Users_action;;
        1) Export 3 "$msg1" "$info";;
        255) Esc;;
    esac
}

Users_log() {
    local msg=""
    local uname=$(id -nu $UID)
    local date30=$(date -v -30d "+%b%e %T")
    local info=$(cat /var/log/auth.log \
        | grep COMMAND \
        | awk -F ';' -v dd="$date30" '{ \
            split($1, a, " "); \
            if (a[1] " " a[2] " " a[3] > dd) print a[6],$4,"on",a[1],a[2],a[3]}' \
        | sed -e "s/ COMMAND=/used sudo to do /p" \
        | grep "^$uname")

    dialog \
        --title "Sudo log" \
        --clear \
        --yes-label "OK" \
        --no-label "Export" \
        --cr-wrap \
        --no-collapse \
        --scrollbar \
        --yesno "$info" 20 110

    local result=$?
    case $result in
        0) Users_action;;
        1) Export 4 "$msg" "$info";;
        255) Esc;;
    esac
}

Export() {
    local funcnum=$1
    local msg=$2
    local info=$3
    local extra=$4

    filepath=$(dialog \
        --title "Export to file" \
        --clear \
        --stdout \
        --inputbox "Enter the path (either absolute or relative):" 20 60)
    
    local result=$?
    if [ $result -eq 0 -o $result -eq 1 ]; then
        if [ $result -eq 0 ]; then
            local pre=$(pwd)
            local realpath=""
            local absolute=$(echo "$filepath" | grep "^/")

            if [ "$absolute" = "" ]; then
                realpath="${pre}/${filepath}"
            else
                realpath="$filepath"
            fi

            if [ "$msg" = "" ]; then
                echo -e "$info" > "$realpath"
            else
                echo -e "${msg}\n${info}" > "$realpath"
            fi
        fi
        case $funcnum in
            1) Users_group;;
            2) Users_port_detail "$extra";;
            3) Users_history;;
            4) Users_log;;
        esac
    elif [ $result -eq 255 ]; then
        Esc
    fi
}

Error_msg() {
    local funcnum=$1
    local msg=$2

    dialog \
        --title "Error message" \
        --clear \
        --colors \
        --msgbox "\Z5$msg" 20 60

    local result=$?
    case $result in
        0) 
            case $funcnum in
                1) Announcement_list;;
                2) Users_action;;
            esac
            ;;
        255) Esc;;
    esac
}

Exit() {
    clear
    echo "Exit." >&1 
    exit 0
}

Esc() {
    clear
    echo "Esc pressed." >&2
    exit 1
}

Interrupt() {
    clear
    echo "Ctrl + C pressed." >&1
    exit 2
}

Entrance
