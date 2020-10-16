#!/bin/bash

export SOURCE_ROOT=`pwd`
export PATH=$SOURCE_ROOT/go/bin:$PATH
export GOROOT=$SOURCE_ROOT/go
export GOPATH=$SOURCE_ROOT
export JAVA_HOME=$SOURCE_ROOT/jdk-11.0.3+7
export PATH=$JAVA_HOME/bin:$PATH
export CC=/usr/bin/gcc
export CXX=/usr/bin/g++
export PATH=$PATH:$SOURCE_ROOT/bazel/output/
export PATH=/usr/local/bin:$PATH
export PATH=$SOURCE_ROOT/gn/out:$PATH
export 'BAZEL_BUILD_ARGS=--local_ram_resources=12288 --local_cpu_resources=8 --verbose_failures --test_env=ENVOY_IP_TEST_VERSIONS=v4only --test_output=errors'
