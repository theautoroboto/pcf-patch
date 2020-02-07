#!/bin/bash

#set -xe

##############################
# VARS
##############################
    #COMMON
    export OM_TARGET=https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}
    export OM_CLIENT_ID=${OPSMAN_CLIENT_ID}
    export OM_CLIENT_SECRET=${OPSMAN_PASSWORD}

    download_product(){
        #How can we turn this into a regex?
        # current_ver=$(om -k staged-products -f json | jq -r --arg name "${PRODUCT_SLUG}" '.[] | select(.name == $name) | .version')
        echo "Downloading ${PRODUCT_SLUG} from Pivnet"
        om -k download-product --output-directory . --pivnet-api-token $PIVNET_TOKEN --pivnet-file-glob "*.pivotal" --pivnet-product-slug $PRODUCT_SLUG --product-version-regex $PRODUCT_VERSION --stemcell-iaas azure
        echo "Uploading ${PRODUCT_SLUG} to OpsMan"
        om -k upload-product -p *.pivotal
        echo "Uploading ${PRODUCT_SLUG} Stemcell to OpsMan"
        om -k upload-stemcell -s *.tgz
        echo "Staging ${PRODUCT_SLUG}"
        om -k stage-product --product-name "$PRODUCT_SLUG"  --product-version $(om tile-metadata --product-path "$PRODUCT_SLUG"*.pivotal --product-version true)
        echo "Deleting ${PRODUCT_SLUG} files"
        rm *.pivotal
        rm *.tgz
    }

    install_pasw(){
        ##############################
        # Download/Upload/Stage PAS
        ##############################
        mkdir downloads
        echo "Downloading PASW from Pivnet"
        om -k download-product --output-directory ./downloads --pivnet-api-token $PIVNET_TOKEN --pivnet-file-glob "*.pivotal" --pivnet-product-slug $PRODUCT_SLUG --product-version-regex $PRODUCT_VERSION--stemcell-iaas azure
        om -k download-product --output-directory ./downloads --pivnet-api-token $PIVNET_TOKEN --pivnet-file-glob "winfs-*.zip" --pivnet-product-slug $PRODUCT_SLUG --product-version-regex $PRODUCT_VERSION
        
        unzip -o ./downloads//winfs-*.zip -d ./downloads/
        chmod +x ./downloads/winfs-injector-linux
        echo "Injecting Tile"
        ./downloads/winfs-injector-linux --input-tile ./downloads/*.pivotal --output-tile ./downloads/pasw-injected.pivotal
        
        echo "Uploading PASW to OpsMan"
        om -k upload-product -p ./downloads/pasw-injected.pivotal
        echo "Uploading PASW Stemcell to OpsMan"
        om -k upload-stemcell -s ./downloads/*.tgz
        echo "Staging PASW"
        om -k stage-product --product-name "$PRODUCT_SLUG" --product-version $(om tile-metadata --product-path ./downloads/pasw-injected.pivotal --product-version true)
        echo "Deleting PASW files"
        rm -rf ./downloads
    }

    install_pas(){
        ##############################
        # Download/Upload/Stage PAS
        ##############################
        echo "Downloading PAS from Pivnet"
        om -k download-product --output-directory . --pivnet-api-token $PIVNET_TOKEN --pivnet-file-glob "cf*.pivotal" --pivnet-product-slug $PRODUCT_SLUG --product-version-regex $PRODUCT_VERSION --stemcell-iaas azure
        echo "Uploading PAS to OpsMan"
        om -k upload-product -p "$PRODUCT_SLUG"-*.pivotal
        echo "Uploading PAS Stemcell to OpsMan"
        om -k upload-stemcell -s *.tgz
        echo "Staging PAS"
        om -k stage-product --product-name cf --product-version $(om tile-metadata --product-path "$PRODUCT_SLUG"-*.pivotal --product-version true)
        echo "Deleting PAS files"
        rm "$PRODUCT_SLUG"-*.pivotal
        rm *.tgz
    }

check_specific_product(){
    pivnet login --api-token $PIVNET_TOKEN
    current_ver=$(om -k staged-products -f json | jq -r --arg name "${PRODUCT_SLUG}" '.[] | select(.name == $name) | .version')

    #There must be a better way
    if [[ $current_ver == *"build"* ]] ; then
        current_ver=$(echo $current_ver | cut -d '-' -f 1)
    fi

    minor=$(echo $current_ver | cut -d '.' -f 1-2)
    echo "Current Version is " $current_ver
    echo "Looking for minor version " $minor
    if [[ $PRODUCT_SLUG == "apmPostgres" ]] ; then
        name="apm"
    fi
    pivnet_ver=$(pivnet releases -p $PRODUCT_SLUG --format json | jq --arg minor $minor '.[] | select(.version|test($minor)).version' | head -n 1 | cut -d '"' -f 2)
    echo "Latest Pivnet Version is " $pivnet_ver

    #There must be a better way
    if [[ $current_ver == *"build"* ]] ; then
        if [ $(echo $pivnet_ver | cut -d '.' -f 3) -gt $(echo $current_ver | cut -d '-' -f 1 | cut -d '.' -f 3) ] ; then
            true
        fi
    else
        if [ $(echo $pivnet_ver | cut -d '.' -f 3) -gt $(echo $current_ver | cut -d '.' -f 3) ] ; then
            true
        else
            false
        fi
    fi
}

if check_specific_product $PRODUCT_SLUG; then
    echo "y'all best upgrade"
    if [ $PRODUCT_SLUG == "cf" ]; then
        install_pas
    elif [ $PRODUCT_SLUG == "pas-windows" ]; then
        install_pasw
    else
        download_product
    fi
else
    echo "its all good man, no upgraded needed"
fi