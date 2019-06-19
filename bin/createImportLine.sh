#!/usr/bin/env zsh

FILE=$1
SOURCE_FILE=$2
IMPORT_TYPE=$3

CLASS_NAME=`basename -s .js ${FILE}`
CLASS_NAME=`basename -s .graphql ${CLASS_NAME}`
CLASS_NAME=`basename -s .jsx ${CLASS_NAME}`

BASE_DIR=`dirname ${SOURCE_FILE}`

if [[ $IMPORT_TYPE = "1" ]]; then
  RELATIVE_PATH=`realpath --relative-to ${BASE_DIR} ${FILE} | gsed 's/\.js$//'`

  SHORT_CLASS_NAME=`echo ${CLASS_NAME} | gsed 's/^[^_]*_\(.\)/\U\1/'`
  echo -n "import {type ${CLASS_NAME} as ${SHORT_CLASS_NAME}} from \"./$RELATIVE_PATH\";"
else
  RELATIVE_PATH=`realpath --relative-to webpack/assets/javascripts ${FILE} | gsed 's/.jsx\?$//' | gsed 's/^core\///'`
  echo -n "import ${CLASS_NAME} from \"$RELATIVE_PATH\";"
fi
