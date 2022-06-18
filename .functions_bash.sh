#!/bin/bash

declare -xr UI_WIDGET_SELECT_TPL_SELECTED='\e[32m → %s \e[39m'
declare -xr UI_WIDGET_SELECT_TPL_DEFAULT="   \e[37m%s %s\e[39m"
declare -xr UI_WIDGET_MULTISELECT_TPL_SELECTED="\e[32m → %s %s\e[39m"
declare -xr UI_WIDGET_MULTISELECT_TPL_DEFAULT="   \e[37m%s %s\e[39m"
declare -xr UI_WIDGET_TPL_CHECKED="[\U2713]"
declare -xr UI_WIDGET_TPL_UNCHECKED="[ ]"

declare -xg UI_WIDGET_RC=-1

typeof() {
	local type="" resolve_ref=true __ref="" signature=()
	if [[ "$1" == "-f" ]]; then
		resolve_ref=false; shift;
	fi
	__ref="$1"
	while [[ -z "${type}" ]] || ( ${resolve_ref} && [[ "${type}" == *n* ]] ); do
		IFS=$'\x20\x0a\x3d\x22' && signature=($(declare -p "$__ref" 2>/dev/null || echo "na"))
		if [[ ! "${signature}" == "na" ]]; then
			type="${signature[1]}"
		fi
		if [[ -z "${__ref}" ]] || [[ "${type}" == "na" ]] || [[ "${type}" == "" ]]; then
			printf "nil"
			return 0
		elif [[ "${type}" == *n* ]]; then
			__ref="${signature[4]}"
		fi
	done
	case "$type" in
		*i*) printf "number";;
		*a*) printf "array";;
		*A*) printf "map";;
		*n*) printf "reference";;
		*) printf "string";;
    esac
}

array_without_value() {
	local args=() value="${1}" s
    shift
	for s in "${@}"; do
        if [ "${value}" != "${s}" ]; then
            args+=("${s}")
        fi
	done
	echo "${args[@]}"
}

array_contains_value() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

str2hex_echo() {
    local str=${1:-$(cat -)}
    local fmt=""
    local chr
    local -i i
    printf "0x"
    for i in `seq 0 $((${#str}-1))`; do
        chr=${str:i:1}
        printf  "%x" "'${chr}"
    done
}

ui_key_input() {
    local key
    local ord
    local debug=0
    local lowercase=0
    local prefix=''
    local args=()
    local opt

    while (( "$#" )); do
        opt="${1}"
        shift
        case "${opt}" in
            "-d") debug=1;;
            "-l") lowercase=1;;
            "-t") args+=(-t $1); shift;;
        esac
    done
    IFS= read ${args[@]} -rsn1 key 2>/dev/null >&2
    read -sN1 -t 0.0001 k1; read -sN1 -t 0.0001 k2; read -sN1 -t 0.0001 k3
    key+="${k1}${k2}${k3}"
    if [[ "${debug}" -eq 1 ]]; then echo -n "${key}" | str2hex_echo; echo -n " : " ;fi;
    case "${key}" in
        '') key=enter;;
        ' ') key=space;;
        $'\x1b') key=esc;;
        $'\x1b\x5b\x36\x7e') key=pgdown;;
        $'\x1b\x5b\x33\x7e') key=erase;;
        $'\x7f') key=backspace;;
        $'\e[A'|$'\e0A  '|$'\e[D'|$'\e0D') key=up;;
        $'\e[B'|$'\e0B'|$'\e[C'|$'\e0C') key=down;;
        $'\e[1~'|$'\e0H'|$'\e[H') key=home;;
        $'\e[4~'|$'\e0F'|$'\e[F') key=end;;
        $'\e') key=enter;;
        $'\e'?) prefix="a-"; key="${key:1:1}";;
    esac

    if [[ "${#key}" == 1 ]]; then
        ord=$(LC_CTYPE=C printf '%d' "'${key}")
        if [[ "${ord}" -lt 32 ]]; then
            prefix="c-${prefix}"
            ord="$(printf "%X" $((ord + 0x60)))"
            key="$(printf "\x${ord}")"
        fi
        if [[ "${lowercase}" -eq 1 ]]; then
            key="${key,,}"
        fi
    fi

    echo "${prefix}${key}"
}

ui_widget_select() {
    local menu=() keys=() selection=() selection_index=()
    local cur=0 oldcur=0 collect="item" select="one"
    local sel="" marg="" drawn=false ref v=""
    local opt_clearonexit=false opt_leaveonexit=false
    export UI_WIDGET_RC=-1
    while (( "$#" )); do
        opt="${1}"; shift
        case "${opt}" in
            -k) collect="key";;
            -i) collect="item";;
            -s) collect="selection";;
            -m) select="multi";;
            -l) opt_clearonexit=true; opt_leaveonexit=true;;
            -c) opt_clearonexit=true;;
            *)
            if [[ "${collect}" == "selection" ]]; then
                selection+=("${opt}")
            elif [[ "${collect}" == "key" ]]; then
                keys+=("${opt}")
            else
                menu+=("$opt")
            fi;;
        esac
    done

    if [[ "${#menu[@]}" -eq 0 ]]; then
        >&2 echo "No menu items given"
        return 1
    fi

    if [[ "${#keys[@]}" -gt 0 ]]; then
        if [[ "${#keys[@]}" -gt 0 ]] && [[ "${#keys[@]}" != "${#menu[@]}" ]]; then
            >&2 echo "Number of keys do not match menu options!"
            return 1
        fi
        selection_index=()
        for sel in "${selection[@]}"; do
            for ((i=0;i<${#keys[@]};i++)); do
                if [[ "${keys[i]}" == "${sel}" ]]; then
                    selection_index+=("$i")
                fi
            done
        done
    else
        selection_index=(${selection[@]})
    fi

    clear_menu() {
        local str=""
        for i in "${menu[@]}"; do str+="\e[2K\r\e[1A"; done
        echo -en "${str}"
    }

    draw_menu() {
        local mode="${initial:-$1}" check=false check_tpl="" str="" msg="" tpl_selected="" tpl_default="" marg=()

        if ${drawn} && [[ "$mode" != "exit" ]]; then
            str+="\r\e[2K"
            for i in "${menu[@]}"; do str+="\e[1A"; done
        fi
        if [[ "$select" == "one" ]]; then
            tpl_selected="$UI_WIDGET_SELECT_TPL_SELECTED"
            tpl_default="$UI_WIDGET_SELECT_TPL_DEFAULT"
        else
            tpl_selected="$UI_WIDGET_MULTISELECT_TPL_SELECTED"
            tpl_default="$UI_WIDGET_MULTISELECT_TPL_DEFAULT"
        fi

        for ((i=0;i<${#menu[@]};i++)); do
            check=false
            if [[ "$select" == "one" ]]; then
                marg=("${menu[${i}]}")
                if [[ ${cur} == ${i} ]]; then
                    check=true
                fi
            else
                check_tpl="$UI_WIDGET_TPL_UNCHECKED";
                if array_contains_value "$i" "${selection_index[@]}"; then
                    check_tpl="$UI_WIDGET_TPL_CHECKED"; check=true
                fi
                marg=("${check_tpl}" "${menu[${i}]}")
            fi
            if [[ "${mode}" != "exit" ]] && [[ ${cur} == ${i} ]]; then
                str+="$(printf "\e[2K${tpl_selected}" "${marg[@]}")\n";
            elif ([[ "${mode}" != "exit" ]] && ([[ "${oldcur}" == "${i}" ]] || [[ "${mode}" == "initial" ]])) || (${check} && [[ "${mode}" == "exit" ]]); then
                str+="$(printf "\e[2K${tpl_default}" "${marg[@]}")\n";
            elif [[ "${mode}" -eq "update" ]] && [[ "${mode}" != "exit" ]]; then
                str+="\e[1B\r"
            fi
        done
        echo -en "${str}"
        export drawn=true
    }

    draw_menu initial

    while true; do
        oldcur=${cur}
        key=$(ui_key_input)
        case "${key}" in
            up|left|i|j) ((cur > 0)) && ((cur--));;
            down|right|k|l) ((cur < ${#menu[@]}-1)) && ((cur++));;
            home)  cur=0;;
            pgup) let cur-=5; if [[ "${cur}" -lt 0 ]]; then cur=0; fi;;
            pgdown) let cur+=5; if [[ "${cur}" -gt $((${#menu[@]}-1)) ]]; then cur=$((${#menu[@]}-1)); fi;;
            end) ((cur=${#menu[@]}-1));;
            space)
                if [[ "$select" == "one" ]]; then
                    continue
                fi
                if ! array_contains_value "$cur" "${selection_index[@]}"; then
                    selection_index+=("$cur")
                else
                    selection_index=($(array_without_value "$cur" "${selection_index[@]}"))
                fi
                ;;
            enter)
                if [[ "${select}" == "multi" ]]; then
                    export UI_WIDGET_RC=()
                    for i in ${selection_index[@]}; do
                        if [[ "${#keys[@]}" -gt 0 ]]; then
                            export UI_WIDGET_RC+=("${keys[${i}]}")
                        else
                            export UI_WIDGET_RC+=("${i}")
                        fi
                    done
                else
                    if [[ "${#keys[@]}" -gt 0 ]]; then
                        export UI_WIDGET_RC="${keys[${cur}]}";
                    else
                        export UI_WIDGET_RC=${cur};
                    fi
                fi
                if $opt_clearonexit; then clear_menu; fi
                if $opt_leaveonexit; then draw_menu exit; fi
                return
                ;;
            [1-9])
                let "cur = ${key}"
                if [[ ${#menu[@]} -gt 9 ]]; then
                    echo -n "${key}"
                    sleep 1
                    key="$(ui_key_input -t 0.5 )"
                    if [[ "$key" =~ [0-9] ]]; then
                        let "cur = cur * 10 + ${key}"
                    elif [[ "$key" != "enter" ]]; then
                        echo -en "\e[2K\r$key invalid input!"
                        sleep 1
                    fi
                fi
                let "cur = cur - 1"
                if [[ ${cur} -gt ${#menu[@]}-1 ]]; then
                    echo -en "\e[2K\rinvalid index!"
                    sleep 1
                    cur="${oldcur}"
                fi
                echo -en "\e[2K\r"
                ;;
            esc|q|$'\e')
                if $opt_clearonexit; then clear_menu; fi
                return 1;;
        esac

        draw_menu update
    done
}

create_repository() {
  clear

  echo -e "\033[0;33m\e[1mProject Name?\e[0m\033[0m"
	read project_name

  clear

  echo -e "\033[0;33m\e[1mWhat is the visibility of the Project?\e[0m\033[0m"
  ui_widget_select -k yes no -i "Public" "Private"

	visibility="${UI_WIDGET_RC}"

  if [ "$visibility" = yes ]; then
    visibility="--public"
  else
		visibility="--private"
  fi

  clear

  echo -e "\033[0;33m\e[1mDo you want to use some Template?\e[0m\033[0m"
  options=(
    "None."
    "Nextjs, Styled-Components, Redux Toolkit, PWA and Typescript."
    "React, Webpack, Styled-Components, Redux Toolkit and Typescript."
    "React, Vite, Styled-Components, Redux Toolkit and Typescript."
    )
  ui_widget_select -l "${options[@]}"

  use_template="${UI_WIDGET_RC}"

  if [[ $use_template -eq 1 ]]; then
    use_template="--template next_styled_components_redux_tlk_pwa_boilerplate"
  elif [[ $use_template -eq 2 ]]; then
    use_template="--template react_webpack_styled_components_redux_tlk_boilerplate"
  elif [[ $use_template -eq 3 ]]; then
    use_template="--template react_vite_styled_components_redux_tlk_boilerplate"
  else
    use_template=''
  fi

  clear

  echo $'\U231B' Creating repository...
  echo

  cd d:/www && gh repo create $project_name $visibility --clone $use_template
  cd d:/www/$project_name
  code .

  clear

  echo
  echo $'\033[0;32m\U2713\033[0m' $project_name "repository created successfully!"

  echo
  echo $'\U231B' 'Close terminal in 20 seconds... to cancel press ESC or ENTER!!!'
  echo

  read -s -N 1 -t 20 -p  "" input

  if [[ $input != $'\x0a' && $input != $'\e' ]]; then
    exit
  fi
}

delete_repository() {
    clear

    echo -e "\033[0;33m\e[1mWhat is the name of the repository you want to delete?\e[0m\033[0m"
    read dele_repo

    echo

    echo -e "\033[0;33m\e[1mExclude which repositories?\e[0m\033[0m"
    options=("Remote" "Local")
    ui_widget_select -l -m -s 0 1 -i "${options[@]}"
    echo

    resositories="${UI_WIDGET_RC[@]}"

    del_local_repo() {
        echo $'\U231B' "Deleting local repository..."
        cd d:/www
        rm -rf $dele_repo
        echo
        echo Local:
        echo $'\033[0;32m\U2713\033[0m' Deleted repository d:/www/$dele_repo
        echo
    }

    del_remote_repo() {
        echo Remote:
        gh repo delete $dele_repo --confirm
        echo
    }

    if [[ $resositories = 0 ]]; then
        del_remote_repo
    elif [[ $resositories = 1 ]]; then
        del_local_repo
    elif [[ $resositories = "0 1" ]]; then
        del_remote_repo
        del_local_repo
    else
        echo
        echo '##############|   No repository deleted.   |##############'
    fi
}
