#!/bin/bash
# © Copyright IBM Corporation 2020
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB-Connector-ODBC/3.1.7/build_mariadb_connector_odbc.sh
# Execute build script: bash build_mariadb_connector_odbc.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mariadb-connector-odbc"
PACKAGE_VERSION="3.1.10"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB-Connector-ODBC/3.1.7/patch"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

# Set the Distro ID
    source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    # Remove artifacts
    cd $SOURCE_ROOT/mariadb-connector-odbc
    rm -rf ma_connection.c.patch
    rm -rf mariadb_stmt.c.patch
    rm -rf basic.c.patch
    rm -rf param.c.patch
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Download MariaDB Connector/ODBC source code
    cd $SOURCE_ROOT
    git clone https://github.com/MariaDB/mariadb-connector-odbc.git
    cd mariadb-connector-odbc
    git checkout ${PACKAGE_VERSION}

    git submodule init
    git submodule update

    #Code changes
    curl -SL -o ma_connection.c.patch $PATCH_URL/ma_connection.c.patch
    patch -l $SOURCE_ROOT/mariadb-connector-odbc/ma_connection.c ma_connection.c.patch

    curl -SL -o basic.c.patch $PATCH_URL/basic.c.patch
    patch -l $SOURCE_ROOT/mariadb-connector-odbc/test/basic.c basic.c.patch

    curl -SL -o param.c.patch $PATCH_URL/param.c.patch
    patch -l $SOURCE_ROOT/mariadb-connector-odbc/test/param.c param.c.patch

    #Build and install
    case "$DISTRO" in
        "ubuntu"*)
            echo $DISTRO
            cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCONC_WITH_UNIT_TESTS=Off  -DWITH_SSL=OPENSSL -DCMAKE_INSTALL_PREFIX=/usr/local  -DODBC_LIB_DIR=/usr/lib/s390x-linux-gnu/
            cmake --build . --config RelWithDebInfo
            sudo make install
            ;;
        "sles"* | "rhel"*)
            echo $DISTRO
            cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCONC_WITH_UNIT_TESTS=Off  -DWITH_SSL=OPENSSL -DCMAKE_INSTALL_PREFIX=/usr/local
            cmake --build . --config RelWithDebInfo
            sudo make install
            ;;
    esac

    printf -- "\n* MariaDB Connector ODBC installed successfully *\n"

    #Run Tests
    runTest
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then

        printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

        # Start MariaDB server and configure for testing
        sudo mysql_install_db --user=mysql
        sleep 20s
        sudo mysqld_safe --user=mysql &
        sleep 30s
        case $DISTRO in
            "ubuntu"*)
                sudo ln -s /var/run/mysqld/mysqld.sock /tmp/mysql.sock
                sleep 1m
                sudo mysql -u root -e "USE mysql; UPDATE user SET plugin='mysql_native_password' WHERE User='root'; FLUSH PRIVILEGES;"
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS test;"
                ;;
            "rhel"*)
                sudo ln -s /var/lib/mysql/mysql.sock /tmp/mysql.sock
                ;;
            "sles"*)
                sudo ln -s /run/mysql/mysql.sock /tmp/mysql.sock
                ;;
        esac

        mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('rootpass');"

        #Set Environment Variables
        export TEST_DRIVER=maodbc_test
        export TEST_SCHEMA=test
        export TEST_DSN=maodbc_test
        export TEST_UID=root
        export TEST_PASSWORD=rootpass
        #Run tests
        cd $SOURCE_ROOT/mariadb-connector-odbc/test
        export ODBCINI=$PWD
        export ODBCSYSINI=$PWD
        sed -i 's//PASSWORD    =/PASSWORD    =rootpass/' $SOURCE_ROOT/mariadb-connector-odbc/test/odbc.ini
        ctest 2>&1 |& tee -a "$LOG_FILE"
        mysqladmin -u root --password="rootpass" shutdown
        case $DISTRO in
            "rhel-7.8" | "rhel-7.9")
                if cat "$LOG_FILE" | grep -q "odbc_connstring (Failed)"; then
                    echo "Expected failures found!"
                    exit 0
                else
                    echo "Unexpected failures found! Please check the logs for details!"
                    exit 1
                fi
                ;;
            "sles"*)
                if cat "$LOG_FILE" | grep -q "odbc_prepare (Failed)"; then
                    echo "Expected failures found!"
                    exit 0
                else
                    echo "Unexpected failures found! Please check the logs for details!"
                    exit 1
                fi
                ;;
        esac
    fi
    set -e
}
function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " build_mariadb-connector-odbc.sh  [-d debug] [-y install-without-confirmation] [-t install-with-test]"
    echo
}

while getopts "h?dyt" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    y)
        FORCE="true"
        ;;
    t)
        TESTS="true"
        ;;
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "*                     Getting Started                 * \n"
    printf -- "         You have successfully installed MariaDB Connector/ODBC. \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y mariadb-server unixodbc-dev git cmake gcc libssl-dev tar curl libcurl4-openssl-dev libkrb5-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y patch mariadb mariadb-server unixODBC unixODBC-devel git cmake gcc openssl-devel openssl tar curl libcurl-devel krb5-devel make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
 "sles-12.5" | "sles-15.1" | "sles-15.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y patch mariadb unixODBC unixODBC-devel git cmake gcc libopenssl-devel openssl glibc-locale tar curl libcurl-devel krb5-devel pcre-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
