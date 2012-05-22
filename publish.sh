#!/usr/bin/env bash

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Define
DEVELOPMENT_URL="site-jdf.rhcloud.com"
DEVELOPMENT_SSH_USERNAME="f35451447e0d4bfbaf37c8a039bb5e6a"
DEVELOPMENT_REPO="ssh://${DEVELOPMENT_SSH_USERNAME}@${DEVELOPMENT_URL}/~/git/site.git/"
DEVELOPMENT_CHECKOUT_DIR=$DIR/_tmp/development

JBORG_DIR="jdf"
JBORG_REPO="filemgmt.jboss.org:www_htdocs"

STAGING_URL="jboss.org/${JBORG_DIR}/stage"
STAGING_DIR="${JBORG_DIR}/stage"

PRODUCTION_URL="jboss.org/${PRODUCTION_DIR}"
PRODUCTION_DIR="${JBORG_DIR}"

clean_site() {
  echo "**** Cleaning _site  ****"
  rm -rf $DIR/_site
}

clean_tmp() {
  echo "**** Cleaning _tmp  ****"
  rm -rf $DIR/_tmp
}

development() {
  clean_site
  echo "**** Generating site ****"
  awestruct -Pdevelopment

  if [ ! -d "$DEVELOPMENT_CHECKOUT_DIR/.git" ]; then
    echo "**** Cloning OpenShift repo ****"
    mkdir -p $DEVELOPMENT_CHECKOUT_DIR
    git clone $DEVELOPMENT_REPO $DEVELOPMENT_CHECKOUT_DIR
  fi

  cp -rf $DIR/_site/* $DEVELOPMENT_CHECKOUT_DIR/php


  echo "**** Publishing site to http://${DEVELOPMENT_URL} ****"
  cd $DEVELOPMENT_CHECKOUT_DIR
  git add *
  git commit -a -m"deploy"
  git push -f
  clean_site
}

production() {
  clean_site
  echo "**** Generating site ****"
  awestruct -Pproduction

  echo "**** Publishing site to http://${PRODUCTION_URL} ****"
  rsync -Pqr --protocol=28 $DIR/_site/* ${JBORG_DIR}@${JBORG_REPO}/${PRODUCTION_DIR}

  clean_site
}

staging() {
  clean_site
  echo "**** Generating site ****"
  awestruct -Pstaging

  echo "**** Publishing site to http://${STAGING_URL} ****"
  rsync -Pqr --protocol=28 $DIR/_site/* ${JBORG_DIR}@${JBORG_REPO}/${STAGING_DIR}

  clean_site
}


usage() {
  cat << EOF
usage: $0 options

This script publishes the JDF site, either to development, staging or to production

OPTIONS:
   -d      Publish *development* version of the site to http://${DEVELOPMENT_URL}
   -s      Publish staging version of the site to http://${STAGING_URL}
   -p      Publish production version of the site to http://${PRODUCTION_URL}
EOF
}

while getopts "spd" OPTION

do
     case $OPTION in
         s)
             staging
             exit
             ;;
         d)
             development
             exit
             ;;
         p)
             production
             exit
             ;;
         h)
             usage
             exit
             ;;
         [?])
             usage
             exit
             ;;
     esac
done

usage
