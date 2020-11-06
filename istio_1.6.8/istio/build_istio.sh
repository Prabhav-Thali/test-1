#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Istio/1.3.6/build_istio.sh
# Execute build script: bash build_istio.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="istio"
PACKAGE_VERSION="1.6.8"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/vibhutisawant/test/master/istio_1.6.8/istio/patch"
HELM_REPO_URL="https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3"
PROXY_REPO_URL="https://raw.githubusercontent.com/vibhutisawant/diff-repo/master/final_patches/istio_proxy.sh"
RUBY_REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Ruby/2.7.2/build_ruby.sh"
ISTIO_REPO_URL="https://github.com/istio/istio.git"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
PROXY_DEBUG_BIN_PATH="$SOURCE_ROOT/proxy/debug"
PROXY_RELEASE_BIN_PATH="$SOURCE_ROOT/proxy/release"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
	mkdir -p "$SOURCE_ROOT/logs/"
fi

#
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n'
	else
		if [[ "${ID}" != "ubuntu" ]]; then
			printf -- '\nFollowing packages are needed before going ahead\n'
			printf -- 'Istio Proxy version: $PACKAGE_VERSION\n'
			printf -- 'Helm version: 3.4.3  \n'
			printf -- '\nBuild might take some time, please have patience . \n'
			while true; do
				read -r -p "Do you want to continue (y/n) ? :  " yn
				case $yn in
				[Yy]*)
					break
					;;
				[Nn]*) exit ;;
				*) echo "Please provide Correct input to proceed." ;;
				esac
			done
		fi
	fi
}

function runTest() {
	set +e
	cd "${SOURCE_ROOT}"
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running test cases for istio\n'
		cd $GOPATH/src/istio.io/istio
		make BUILD_WITH_CONTAINER=0 test
		printf -- '\n\n COMPLETED TEST EXECUTION !! \n' |& tee -a "$LOG_FILE"
	fi
	set -e
}

function cleanup() {
	rm -rf "${SOURCE_ROOT}/glide-v0.13.0-linux-s390x.tar.gz"
	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function buildHelm() {
	if [ $(command -v helm) ]; then
		printf -- "helm detected skipping helm installation \n" |& tee -a "$LOG_FILE"
	else
		#Install Glide
		cd $GOPATH
		wget https://github.com/Masterminds/glide/releases/download/v0.13.0/glide-v0.13.0-linux-s390x.tar.gz
		tar -xzf glide-v0.13.0-linux-s390x.tar.gz
		export PATH=$GOPATH/linux-s390x:$PATH
           
		# Download and configure helm
		export VERIFY_CHECKSUM=false
		curl -fsSL -o get_helm.sh $HELM_REPO_URL
		chmod 700 get_helm.sh
		./get_helm.sh
		export PATH=/usr/local/bin:$PATH
		
		printf -- 'helm installed\n' |& tee -a "$LOG_FILE"
	fi
}

#Installing dependencies
function dependencyInstall() {
	printf -- 'Building dependencies\n' |& tee -a "$LOG_FILE"

	cd "${SOURCE_ROOT}"
	#Build Istio Proxy
	#make a call to istio proxy script
	if [ -f "$PROXY_DEBUG_BIN_PATH" ] && [ -f "$PROXY_RELEASE_BIN_PATH" ]; then
		printf -- "Istio Proxy binaries are found at location %s and %s \n" "$PROXY_DEBUG_BIN_PATH" "$PROXY_RELEASE_BIN_PATH" |& tee -a "$LOG_FILE"
	else
		printf -- 'Building Istio Proxy\n' |& tee -a "$LOG_FILE"
		curl -o build_istio_proxy.sh $PROXY_REPO_URL |& tee -a "$LOG_FILE"
		chmod +x build_istio_proxy.sh
		if [[ "$TESTS" == "true" ]]; then
			printf -- 'Test case flag is enabled \n'
			bash build_istio_proxy.sh -yt
		else
			bash build_istio_proxy.sh -y
		fi

		#set a path to binaries
		printf -- 'Istio Proxy installed successfully\n' |& tee -a "$LOG_FILE"
	fi
	    #set go environment
		export GOPATH="${SOURCE_ROOT}"
		export GOROOT=/usr/local/go
		export PATH=${GOPATH}/bin:${GOROOT}/bin:$PATH
		if [[ "${ID}" == "rhel"  ||  ${ID} == "sles" ]]; then
		   sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
		fi
		go version 
		
		#Install Ruby
		if [[ "${VERSION_ID}" == "7.7"  ||  "${VERSION_ID}" == "7.8"  ||  "${VERSION_ID}" == "7.9" || "${VERSION_ID}" == "12.5" ]]; then
			  printf -- 'Installing Ruby\n'
			  cd "${SOURCE_ROOT}"
			  curl -o build_ruby.sh $RUBY_REPO_URL |& tee -a "$LOG_FILE" 
			  bash build_ruby.sh -y
		fi
		#Install fpm
		export GEM_HOME="$HOME/.gem"
		gem install fpm
		export PATH=$HOME/.gem/bin:$PATH

		#Install go-bindata
		cd $SOURCE_ROOT
		go get github.com/jteeuwen/go-bindata
		cd $GOPATH/src/github.com/jteeuwen/go-bindata/go-bindata
		go build
		sudo cp go-bindata  /usr/local/go/bin/
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'

	cd "${SOURCE_ROOT}"

	# Download and configure Istio
	printf -- '\nDownloading Istio. Please wait.\n'
	mkdir -p $GOPATH/src/istio.io && cd $GOPATH/src/istio.io
	git clone $ISTIO_REPO_URL
	cd istio
	git checkout $PACKAGE_VERSION

	#Patch for setting Path for release and debug envoy binaries
	cd "${GOPATH}/src/istio.io/istio"
	curl -sSL ${PATCH_URL}/istio_build_test_patch.diff | patch -p1 || echo "Error" 
	sed -i "s|\$SOURCE_ROOT_D|${PROXY_DEBUG_BIN_PATH}|"  $GOPATH/src/istio.io/istio/bin/init.sh
    sed -i "s|\$SOURCE_ROOT_R|${PROXY_RELEASE_BIN_PATH}|"  $GOPATH/src/istio.io/istio/bin/init.sh

	#Build Istio
	printf -- '\nBuilding Istio \n'
	cd $GOPATH/src/istio.io/istio
	make BUILD_WITH_CONTAINER=0  gen-charts
	make BUILD_WITH_CONTAINER=0 build
	printenv >>"$LOG_FILE"
	printf -- 'Built Istio successfully \n\n'

	# Run Tests
	runTest
}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo " bash build_istio.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

function printSummary() {

    printf -- "\n* Getting Started * \n"
    printf -- "\n ISTIO BUILD COMPLETED SUCCESSFULLY !!! \n "
    printf -- "\n* To integrate istio with kubernetes, export below variables * \n"
    printf -- "\n export GOPATH=%s""$GOPATH"
    printf -- "\n export GOROOT=%s""$GOROOT"
    printf -- "\n export PATH=\$PATH:\$GOPATH/go/bin:\$GOPATH/bin:\$GOPATH/src/istio.io/istio/out/linux_s390x/:\$GOPATH/linux-s390x \n"
}

logDetails
prepare |& tee -a "$LOG_FILE"
#checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y pkg-config zip tar zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl libcurl3-dev bzip2 mercurial patch ruby ruby-dev rubygems build-essential
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.7" | "rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo yum install -y wget tar make zip unzip git vim binutils-devel bzip2 which automake autoconf libtool zlib pkgconfig zlib-devel curl bison libcurl-devel mercurial ruby-devel gcc make rpm-build rubygems
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"sles-12.5" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget tar make zip unzip git vim binutils-devel bzip2 glibc-devel makeinfo zlib-devel curl which automake autoconf libtool zlib pkg-config libcurl-devel mercurial patch 
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"

	;;
	
 "sles-15.1" | "sles-15.2" )
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget tar make zip unzip git vim binutils-devel bzip2 glibc-devel makeinfo zlib-devel curl which automake autoconf libtool zlib pkg-config libcurl-devel mercurial patch ruby2.5-devel ruby2.5-rubygem-ffi python3-devel python3-pip 
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"
	
	;;
	
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

# Print Summary
printSummary |& tee -a "$LOG_FILE"
