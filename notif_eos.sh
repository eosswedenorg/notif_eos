#!/bin/bash

# todo: make possible to notify more than one telegram url
# todo: make possible to track an account more than once
# todo: add .last_seq to avoid fetching all everytime

# path of this script
NOTIF_EOS_PATH=$(dirname "$0")

# source config file
source ${NOTIF_EOS_PATH}/notif_eos.conf || exit 1

# check dependencies
which ${CLEOS_PATH} > /dev/null || exit 1
which curl          > /dev/null || exit 1
which jq            > /dev/null || exit 1
which base64        > /dev/null || exit 1

notif_msg()
{
    # usage: notif_msg 'this is sent to the telegram group via api configured'
    if [ $# -ne 1 ]; then
        return 1
    fi

    # send the message
    curl --data chat_id="${TELEGRAM_CHAT}" \
         --data-urlencode "text=$(echo -ne ${1})" "${TELEGRAM_SEND}" \
         > /dev/null 2>&1
}

notif_eos()
{
    # usage: notif_eos 'account_name' 'jq_expression'
    if [ $# -ne 2 ]; then
        return 1
    fi

    # grab the last actions of the given account
    current_page=$(${CLEOS_PATH} get actions -j ${1})

    # grab all actions
    while true
    do
        # grab the page's first action's seq.
        first_seq=$(echo ${current_page} | jq '.actions[0].account_action_seq')

        # grab last
        last_seq=$(echo ${current_page} | jq '.actions[-1].account_action_seq')

        # determine page size
        page_size=$(( ${last_seq} - ${first_seq} ))

        # print to fd1
        echo ${current_page} | jq -c ${2}

        # paginate
        next_seq=$(( ${first_seq} - ${page_size} - 1 ))
        if [ ${next_seq} -lt 0 ]; then
            next_seq=0
            page_size=$(( ${first_seq} - 1 ))
        fi
        if [ ${page_size} -lt 0 ]; then
            break
        fi

        # grab next page
        current_page=$(${CLEOS_PATH} get actions -j ${account} ${next_seq} ${page_size})
    done
}

# iterate over accounts to track with their respective jq expressions
for arg in $(echo "${TRACK_ACCOUNTS}" | jq -r '.[] | @base64')
do
    # use base64 to avoid issues with \n and ' '
    _jq() {
        echo ${arg} | base64 --decode | jq -r ${1}
    }

    # init. params
    account=$(_jq '.account_name')
    jqexpr=$(_jq '.jq_expression')

    # init. files
    if [ ! -f ${NOTIF_EOS_PATH}/.notif_${account} ]; then
        touch ${NOTIF_EOS_PATH}/.notif_${account}
    fi
    if [ ! -f ${NOTIF_EOS_PATH}/.count_${account} ]; then
        echo 0 > ${NOTIF_EOS_PATH}/.count_${account}
    fi

    # grab them again
    notif_eos ${account} ${jqexpr} > ${NOTIF_EOS_PATH}/.notif_${account}

    # count them
    old_count=$(cat ${NOTIF_EOS_PATH}/.count_${account})
    new_count=$(cat ${NOTIF_EOS_PATH}/.notif_${account} | wc -l)

    # send message if there are new notifications
    if [ ${new_count} -gt ${old_count} ]; then
        new_msg_amnt=$(( ${new_count} - ${old_count} ))
        message=$(cat ${NOTIF_EOS_PATH}/.notif_${account} | tail -n ${new_msg_amnt})

        if [ ${old_count} -gt 0 ]; then
            notif_msg ${message}
        fi

        # store new count
        echo ${new_count} > ${NOTIF_EOS_PATH}/.count_${account}
    fi
done

