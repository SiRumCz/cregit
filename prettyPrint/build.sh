#!/bin/bash

LOCAL_PREVIEW=yes
DATABASE_UPDATE=no # yes: update activity database, no: will directly use database
PRINT_OPTION=recursively # options: recursively|single|no
TABLE_POS_BOTTOM=no # default: place contributor table on top of page

OUTPUT_DIR="/home/zkchen/public_html"
HOST_URL="http://o.cs.uvic.ca:20810/~zkchen"

#GIT_URL="http://github.com/git/git"
#HOME_REPO="/home/zkchen/cregit-data/git"
#ORIGINAL_REPO="${HOME_REPO}/original.repo-v2.17/git"
#BLAME_DIRECTORY="${HOME_REPO}/v2.17/blame"
#TOKEN_DIRECTORY="${HOME_REPO}/v2.17/token.line"
#PERSONS_DB="${HOME_REPO}/v2.17/persons-gender-2.17.db"
#TOKEN_DB="${HOME_REPO}/v2.17/token.db"
#BLAMETOKENS_DB="${HOME_REPO}/v2.17/blame-tokens.db"

GIT_URL="https://github.com/torvalds/linux"
HOME_REPO="/home/zkchen/cregit-data/linux"
ORIGINAL_REPO="${HOME_REPO}/linux-zkchen"
BLAME_DIRECTORY="${HOME_REPO}/4.17/blame"
TOKEN_DIRECTORY="${HOME_REPO}/4.17/token.withLines"
PERSONS_DB="${HOME_REPO}/linux-persons-gender.db"
TOKEN_DB="${HOME_REPO}/token.db"
BLAMETOKENS_DB="${HOME_REPO}/blame_4_17.db"

DIRVIEWPATH="root/kernel" # starting directory for generating directory view

OPTIONS="--filter-lang=c --verbose --overwrite"
DIRVIEWFLAGS="${OPTIONS}"
FLAGS="${OPTIONS} --git-url=${GIT_URL}"

if [ "$LOCAL_PREVIEW" = "yes" ]; then
	FLAGS+=" --webroot-relative"
	DIRVIEWFLAGS+=" --webroot-relative"
else
	FLAGS+=" --webroot=${HOST_URL}"
	DIRVIEWFLAGS+=" --webroot=${HOST_URL}"
fi

if [ "$DATABASE_UPDATE" = "yes" ]; then
	DIRVIEWFLAGS+=" --dbupdate"
fi

if [ "$PRINT_OPTION" = "recursively" ]; then
    DIRVIEWFLAGS+=" --print-recursive"
elif [ "$PRINT_OPTION" = "single" ]; then
    DIRVIEWFLAGS+=" --print-single"
fi

if [ "$TABLE_POS_BOTTOM" = "yes" ]; then
    DIRVIEWFLAGS+=" --table-bottom"
fi

set -x
#perl prettyPrint.pl ${FLAGS} "${ORIGINAL_REPO}" "${BLAME_DIRECTORY}" "${TOKEN_DIRECTORY}" "${TOKEN_DB}" "${PERSONS_DB}" "${OUTPUT_DIR}"
perl prettyPrintDirView.pl ${DIRVIEWFLAGS} "${DIRVIEWPATH}" "${ORIGINAL_REPO}" "${TOKEN_DB}" "${PERSONS_DB}" "${BLAMETOKENS_DB}" "${OUTPUT_DIR}"
cp -r templates/public/. ${OUTPUT_DIR}/public

