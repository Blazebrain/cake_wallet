#!/bin/sh

APP_MACOS_NAME=""
APP_MACOS_VERSION=""
APP_MACOS_BUILD_VERSION=""
APP_MACOS_BUNDLE_ID=""

MONERO_COM="monero.com"
CAKEWALLET="cakewallet"

TYPES=($MONERO_COM $CAKEWALLET)
APP_MACOS_TYPE=$1

if [ -n "$1" ]; then
	APP_MACOS_TYPE=$1
fi

MONERO_COM_NAME="Monero.com"
MONERO_COM_VERSION="1.8.1"
MONERO_COM_BUILD_NUMBER=37
MONERO_COM_BUNDLE_ID="com.cakewallet.monero"

CAKEWALLET_NAME="Cake Wallet"
CAKEWALLET_VERSION="1.14.1"
CAKEWALLET_BUILD_NUMBER=96
CAKEWALLET_BUNDLE_ID="com.fotolockr.cakewallet"

if ! [[ " ${TYPES[*]} " =~ " ${APP_MACOS_TYPE} " ]]; then
    echo "Wrong app type."
    exit 1
fi

case $APP_MACOS_TYPE in
	$MONERO_COM)
		APP_MACOS_NAME=$MONERO_COM_NAME
		APP_MACOS_VERSION=$MONERO_COM_VERSION
		APP_MACOS_BUILD_NUMBER=$MONERO_COM_BUILD_NUMBER
		APP_MACOS_BUNDLE_ID=$MONERO_COM_BUNDLE_ID;;
	$CAKEWALLET)
		APP_MACOS_NAME=$CAKEWALLET_NAME
		APP_MACOS_VERSION=$CAKEWALLET_VERSION
		APP_MACOS_BUILD_NUMBER=$CAKEWALLET_BUILD_NUMBER
		APP_MACOS_BUNDLE_ID=$CAKEWALLET_BUNDLE_ID;;
esac

export APP_MACOS_TYPE
export APP_MACOS_NAME
export APP_MACOS_VERSION
export APP_MACOS_BUILD_NUMBER
export APP_MACOS_BUNDLE_ID
