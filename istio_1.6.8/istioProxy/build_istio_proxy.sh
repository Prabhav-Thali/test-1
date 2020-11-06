#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/1.6.8/build_istio_proxy.sh
# Execute build script: bash build_istio_proxy.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="Istio-Proxy"
PACKAGE_VERSION="1.6.8"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/vibhutisawant/test/master/istio_1.6.8/istioProxy/patch"
ISTIO_PROXY_REPO_URL="https://github.com/istio/proxy.git"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TESTS="false"
PROXY_DEBUG_BIN_PATH="$SOURCE_ROOT/proxy/debug"
PROXY_RELEASE_BIN_PATH="$SOURCE_ROOT/proxy/release"
GOPATH="$SOURCE_ROOT"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
	mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {

	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message'
	else
		printf -- '\nFollowing packages are needed before going ahead\n'
		printf -- '1:Bazel\t\tVersion: 2.2.0\n'
		printf -- '2:Envoy\n'
		printf -- '3:BoringSSL\n'
		printf -- '4:GCC\t\tVersion: gcc-9.3.0 \n'
		printf -- '5:Go\t\tVersion: go1.14.2\n\n'

		printf -- '\nBuild might take some time.Sit back and relax'
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
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
		cd "${SOURCE_ROOT}/proxy"
		make BUILD_WITH_CONTAINER=0 test
		printf -- 'Istio proxy tests completed successfully.\n' |& tee -a "$LOG_FILE"
	fi
	set -e
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
	rm -rf "${SOURCE_ROOT}/cmake-3.7.2.tar.gz"
	rm -rf "${SOURCE_ROOT}/go1.14.2.linux-s390x.tar.gz"
	rm -rf "${SOURCE_ROOT}/gcc-9.3.0.tar.gz"
	rm -rf "${SOURCE_ROOT}/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.3_7.tar.gz"
}

function buildGCC() {

	printf -- 'Building GCC \n' |& tee -a "$LOG_FILE"
	cd "${CURDIR}"
	wget https://ftp.gnu.org/gnu/gcc/gcc-9.3.0/gcc-9.3.0.tar.gz
	tar -xf gcc-9.3.0.tar.gz
	cd gcc-9.3.0/
	./contrib/download_prerequisites
	mkdir gcc_build
	cd gcc_build/
	../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
		--build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu \
		--enable-threads=posix --with-system-zlib --disable-multilib
	make -j8
	sudo make install
	sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
	sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
	sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
	export PATH=/opt/gcc/bin:"$PATH"
	export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/9.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/9.3.0/include
	sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.28 /lib64/libstdc++.so.6
	sudo ln -sf /opt/gcc/lib64/libatomic.so.1 /lib64/libatomic.so.1

	printf -- 'Built GCC successfully \n' |& tee -a "$LOG_FILE"

}


function buildGO() {
	cd "${SOURCE_ROOT}"
	if command -p "go" version | grep 1.14.2 >/dev/null; then
		printf -- "Go detected\n"
	else
		printf -- 'Installing go\n'
		cd "${SOURCE_ROOT}"	
		wget https://storage.googleapis.com/golang/go1.14.2.linux-s390x.tar.gz
		chmod ugo+r  go1.14.2.linux-s390x.tar.gz
        sudo rm -rf /usr/local/go /usr/bin/go
 		sudo tar -C /usr/local -xzf go1.14.2.linux-s390x.tar.gz
        sudo ln -sf /usr/local/go/bin/go /usr/bin/ 
        sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
		export GOPATH=${SOURCE_ROOT}
		export GOROOT=/usr/local/go
		if [[ "${ID}" == "rhel" ||  ${ID} == "sles" ]]; then
		   sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
		fi
		go version 
		printf -- 'go installed\n'
	fi
}
function installDependency() {
	printf -- 'Installing dependencies\n' |& tee -a "$LOG_FILE"
	#only for rhel
	if [[ "${VERSION_ID}" == "7.7"  || "${VERSION_ID}" == "7.8" || "${VERSION_ID}" == "7.9" ]]; then
		cd "${CURDIR}"
		wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
		tar xzf cmake-3.7.2.tar.gz
		cd cmake-3.7.2
		./configure --prefix=/usr/local
		make -j8 && sudo make install
		printf -- 'Built cmake successfully \n' |& tee -a "$LOG_FILE"
		
		cd "${CURDIR}"
		printf -- 'Building GIT \n' |& tee -a "$LOG_FILE"
		wget https://github.com/git/git/archive/v2.17.1.tar.gz
		tar -zxf v2.17.1.tar.gz
		cd git-2.17.1
		make configure
		./configure --prefix=/usr
		make -j8 && sudo make install
		printf -- 'Built GIT successfully \n' |& tee -a "$LOG_FILE"
	fi
	printf -- 'Installing Java\n' |& tee -a "$LOG_FILE"
	cd "${SOURCE_ROOT}"
	wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.3%2B7/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.3_7.tar.gz
	tar -xvf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.3_7.tar.gz
	export JAVA_HOME=${SOURCE_ROOT}/jdk-11.0.3+7
	export PATH=$JAVA_HOME/bin:$PATH
	java -version |& tee -a "$LOG_FILE"
	printf -- 'java installed\n' |& tee -a "$LOG_FILE"
	#export CC even if bazel is pre-installed
    
	printf -- 'Downloading Bazel\n' |& tee -a "$LOG_FILE"
	if command "bazel" version | grep 2.2.0 >/dev/null; then
		printf -- 'Bazel detected\n' |& tee -a "$LOG_FILE"
	else
		#Bazel download
		cd "${SOURCE_ROOT}"
		mkdir bazel && cd bazel
		wget https://github.com/bazelbuild/bazel/releases/download/2.2.0/bazel-2.2.0-dist.zip
		unzip bazel-2.2.0-dist.zip
		chmod -R +w .
		export CC=/usr/bin/gcc
		export CXX=/usr/bin/g++
		
		cd "${SOURCE_ROOT}"
		curl -o patch_BUILD.patch $PATCH_URL/patch_BUILD.patch
		patch "${SOURCE_ROOT}/bazel/third_party/BUILD" patch_BUILD.patch
		curl -o BUILD.diff $PATCH_URL/BUILD.diff
		patch "${SOURCE_ROOT}/bazel/src/main/java/com/google/devtools/build/lib/syntax/BUILD" BUILD.diff
		cd ${SOURCE_ROOT}/bazel
		env EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk" bash ./compile.sh
		export PATH=${SOURCE_ROOT}/bazel/output/:$PATH
		bazel version |& tee -a "$LOG_FILE"
		printf -- 'Bazel installed\n' |& tee -a "$LOG_FILE"
	fi
	
	printf -- 'Installing Ninja\n' |& tee -a "$LOG_FILE"
	
	if [ "${ID}" == "rhel" ] || [ ${VERSION_ID} == 12.5 ]; then
		printf -- '\nDownloading ninja\n' |& tee -a "$LOG_FILE"
		cd "${SOURCE_ROOT}"
		git clone -b v1.8.2 git://github.com/ninja-build/ninja.git && cd ninja
		./configure.py --bootstrap
		if [ "${ID}" == "rhel" ]; then
			sudo ln -sf ${SOURCE_ROOT}/ninja/ninja /usr/local/bin/ninja
			export PATH=/usr/local/bin:$PATH
		else
			sudo ln -sf ${SOURCE_ROOT}/ninja/ninja /usr/bin/ninja
		fi
		ninja --version |& tee -a "$LOG_FILE"
		printf -- '\nninja installed succesfully\n' |& tee -a "$LOG_FILE"
	fi
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'

    #Build gn
    cd "${SOURCE_ROOT}"
    git clone https://gn.googlesource.com/gn
    cd gn
	git checkout c5f5cb2
	sed -i -e 's/-Wl,--icf=all//g' ./build/gen.py
    python build/gen.py
    ninja -C out
	export PATH=$SOURCE_ROOT/gn/out:$PATH
	printf -- '\ngn installed succesfully\n' |& tee -a "$LOG_FILE"
		
	#Envoy download

	cd "${SOURCE_ROOT}"
	printf -- '\nDownloading Envoy\n'
	git clone https://github.com/istio/envoy/
	cd envoy/
    git checkout release-1.6

	#multiple patches to be user here

    if [[ "${ID}" == "rhel" ]]; then
	   curl -sSL ${PATCH_URL}/envoy_rhel.diff | patch -p1 || echo "Error" 
	else
	   curl -sSL ${PATCH_URL}/envoy.diff | patch -p1 || echo "Error"  
	fi
	printf -- 'Envoy installed\n'

	#BoringSSL download
	cd "${SOURCE_ROOT}"
	printf -- '\nDownloading BoringSSL\n'
	git clone https://github.com/linux-on-ibm-z/boringssl
	cd boringssl
	git checkout boringssl-Istio102-s390x
	printf -- 'BoringSSL installed\n'
	printenv >>"$LOG_FILE"


	cd "${SOURCE_ROOT}"
	# Download and configure  Istio Proxy
	printf -- '\nDownloading  Istio Proxy. Please wait.\n'
	git clone -b $PACKAGE_VERSION $ISTIO_PROXY_REPO_URL
	#Apply Patches

	if [ -f "$PROXY_DEBUG_BIN_PATH/envoy" ]; then
		printf -- "Istio Proxy binaries (Debug mode) are found at location $PROXY_DEBUG_BIN_PATH \n"
	else
		#Build Istio Proxy In DEBUG mode
		printf -- '\nBuilding Istio Proxy In DEBUG mode\n'
		printf -- '\nBuild might take some time.Sit back and relax\n'
		cd "${SOURCE_ROOT}/proxy"
		#Patch applied for debug mode
		if [ "${ID}" == "sles" ]; then
			curl -sSL ${PATCH_URL}/Makefile_debug_sles.diff | patch -p1 || echo "Error"
		elif [ "${ID}" == "rhel" ]; then
		    curl -sSL ${PATCH_URL}/Makefile_debug_rhel.diff | patch -p1 || echo "Error"
		else
		    curl -sSL ${PATCH_URL}/Makefile_debug.diff | patch -p1 || echo "Error"
		fi
		cd "${SOURCE_ROOT}/proxy"
		sed -i "s|\$SOURCE_ROOT|${SOURCE_ROOT}|"  ${SOURCE_ROOT}/proxy/WORKSPACE
		export CMAKE_CXX_COMPILER=/usr/bin/g++
		export 'BAZEL_BUILD_ARGS=--local_ram_resources=12288 --local_cpu_resources=8 --verbose_failures --test_env=ENVOY_IP_TEST_VERSIONS=v4only --test_output=errors'
		make BUILD_WITH_CONTAINER=0  build -j8
		mkdir -p "${PROXY_DEBUG_BIN_PATH}"
		cp -r "${SOURCE_ROOT}/proxy/bazel-bin/src/envoy/envoy" "${PROXY_DEBUG_BIN_PATH}/"
		printf -- 'Built Istio Proxy successfully in DEBUG mode\n\n'
	fi

	#Build Istio Proxy In RELEASE mode
	cd "${SOURCE_ROOT}"
	if [ -f "$PROXY_RELEASE_BIN_PATH/envoy" ]; then
		printf -- "Istio Proxy binaries (Release mode) are found at location $PROXY_RELEASE_BIN_PATH \n"
	else
		printf -- '\nBuilding Istio Proxy In RELEASE mode\n'
		#patch applied here
		cd "${SOURCE_ROOT}/proxy"
		git checkout Makefile.core.mk
		if [ "${ID}" == "sles" ]; then
			curl -sSL ${PATCH_URL}/Makefile_release_sles.diff | patch -p1 || echo "Error"
		else 
		    curl -sSL ${PATCH_URL}/Makefile_release.diff | patch -p1 || echo "Error"
 		fi
		printf -- '\nBuild might take some time.Sit back and relax\n'
		cd "${SOURCE_ROOT}/proxy"
		make BUILD_WITH_CONTAINER=0  build -j8
		mkdir -p "$PROXY_RELEASE_BIN_PATH"
		cp -r "${SOURCE_ROOT}/proxy/bazel-bin/src/envoy/envoy" "${PROXY_RELEASE_BIN_PATH}/"
		printf -- 'Built Istio Proxy successfully in RELEASE mode\n\n'
	fi

	#Run tests
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
	echo "  bash build_istio_proxy.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- '\n\nInstallation completed successfully.\n' |& tee -a "$LOG_FILE"
}

logDetails
#checkPrequisites
prepare |& tee -a "$LOG_FILE"

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git pkg-config zip zlib1g-dev unzip python3 libtool automake cmake curl wget build-essential rsync clang libgtk2.0-0 ninja-build clang-format-9 python  software-properties-common apt-transport-https curl gpg-agent 
	sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends g++-9
	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -sf /usr/bin/gcc-9 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-9 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

 "ubuntu-20.04" | "ubuntu-20.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git pkg-config zip zlib1g-dev unzip python3 libtool automake cmake curl wget build-essential rsync clang libgtk2.0-0 ninja-build clang-format-9 python  software-properties-common apt-transport-https curl gpg-agent gcc-9 g++-9
	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -sf /usr/bin/gcc-9 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-9 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y diffutils hostname git tar zip gcc gcc-c++ unzip python2 python3 libtool automake cmake curl wget xz gcc vim patch binutils-devel bzip2 make tcl gettext gcc-toolset-9-libstdc++-devel.s390x ruby-devel gcc make rpm-build rubygems | tee -a "${LOG_FILE}"
	sudo ln -sf /usr/bin/python2 /usr/bin/python
	sudo cp /opt/rh/gcc-toolset-9/root/usr/lib/gcc/s390x-redhat-linux/9/libstdc++.a /usr/lib/gcc/s390x-redhat-linux/8
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;
	
"rhel-7.7" | "rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y hostname git tar zip gcc-c++ unzip python3 libtool automake cmake curl wget gcc vim patch binutils-devel bzip2 make tcl gettext | tee -a "${LOG_FILE}"
    buildGCC
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;
		

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget git tar pkg-config zip unzip python3 libtool automake cmake zlib-devel gcc9 gcc9-c++ binutils-devel patch which curl python-xml 
	sudo ln -sf /usr/bin/gcc-9 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-9 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;

"sles-15.1" | "sles-15.2")
	sudo zypper install -y wget git tar pkg-config zip unzip python3 libtool automake cmake zlib-devel gcc9 gcc9-c++ binutils-devel patch which curl libxml2-devel ninja gzip awk python python-xml
	buildGO |& tee -a "$LOG_FILE"
	sudo ln -sf /usr/bin/gcc-9 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-9 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

# Print Summary
printSummary
