#!/bin/bash -x
#
# Sets up a Python testing environment from scratch. Mainly written for Jenkins.
# Works for CPython. Not working for Jython, IronPython and PyPy.
#
# Requirements:
#   A working build environment inside the container with OpenSSL, bzip2,
#   libxml2 and libxslt development files. Only tested on Linux variants.
#
#   Last time we looked, for ubuntu, that meant:
#     $ sudo apt-get install build-essential libssl-dev lilbbz2-dev \
#                                                       libxml2-dev libxslt-dev
#
# Usage:
#   Example:
#
#     $ PYFLAV=cpy-3.3 ./run_tests.sh
#
#   Variables:
#     - PYFLAV: Defaults to 'cpy-2.7'. See other values below.
#     - WORKSPACE: Defaults to $PWD. It's normally set by Jenkins.
#     - MAKEOPTS: Defaults to '-j2'.
#     - MONOVER: Defaults to '2.11.4'. Only relevant for ipy-* flavors.
#
# Jenkins guide:
#   1. Create a 'Multi configuration project'.
#   2. Set up stuff like git repo the usual way.
#   3. In the 'Configuration Matrix' section, create a user-defined axis named
#      'PYVER'. and set it to the Python versions you'd like to test, separated
#      by whitespace. For example: 'cpy-2.7 cpy-3.4'
#   4. Add a new "Execute Shell" build step and type in './run_tests.sh'.
#   5. Add a new "Publish JUnit test report" post-build action and type in
#      'test_result.*.xml'
#   6. Add a new "Publish Cobertura Coverage Report" post-build action and type
#      in 'coverage.xml'. Install the "Cobertura Coverage Report" plug-in if you
#      don't see this option.
#   7. Nonprofit!
#


# Sanitization
[ -z "$PYFLAV" ] && PYFLAV=cpy-2.7;
[ -z "$MONOVER" ] && MONOVER=2.11.4;
[ -z "$WORKSPACE" ] && WORKSPACE="$PWD";
[ -z "$MAKEOPTS" ] && MAKEOPTS="-j2";

PYIMPL=(${PYFLAV//-/ });
PYVER=${PYIMPL[1]};
PYFLAV="${PYFLAV/-/}";
PYFLAV="${PYFLAV/./}";
if [ -z "$PYVER" ]; then
    PYVER=${PYIMPL[0]};
    PYIMPL=cpy;
    PYFLAV=cpy${PYVER/./};
else
    PYIMPL=${PYIMPL[0]};
fi

PYNAME=python$PYVER;

if [ -z "$FN" ]; then
    declare -A URLS;
    URLS["cpy27"]="2.7.18/Python-2.7.18.tar.xz";
    URLS["cpy36"]="3.6.15/Python-3.6.15.tar.xz";
    URLS["cpy37"]="3.7.17/Python-3.7.17.tar.xz";
    URLS["cpy38"]="3.8.17/Python-3.8.17.tar.xz";
    URLS["cpy39"]="3.9.17/Python-3.9.17.tar.xz";
    URLS["cpy310"]="3.10.12/Python-3.10.12.tar.xz";
    URLS["cpy311"]="3.11.4/Python-3.11.4.tar.xz";
    #URLS["cpy312"]="3.12.0/Python-3.12.0.tar.xz";
    URLS["jyt27"]="2.7.1/jython-installer-2.7.1.jar";
    URLS["ipy27"]="ipy-2.7.4.zip";

    FN="${URLS["$PYFLAV"]}";

    if [ -z "$FN" ]; then
        echo "Unknown Python version $PYFLAV";
        exit 2;
    fi;
fi;


# Initialization
IRONPYTHON_URL_BASE=https://github.com/IronLanguages/main/archive;
CPYTHON_URL_BASE=http://www.python.org/ftp/python;
JYTHON_URL_BASE=http://search.maven.org/remotecontent?filepath=org/python/jython-installer;
MAKE="make $MAKEOPTS";


# Set specific variables
if [ $PYIMPL == "cpy" ]; then
    PREFIX="$(basename $(basename $FN .tgz) .tar.xz)";

elif [ $PYIMPL == "ipy" ]; then
    PREFIX="$(basename $FN .zip)";
    MONOPREFIX="$WORKSPACE/mono-$MONOVER"
    XBUILD="$MONOPREFIX/bin/xbuild"

elif [ $PYIMPL == "jyt" ]; then
    PYNAME=jython;
    PREFIX="$(basename $FN .jar)";
fi;

# Set common variables
PYTHON="$WORKSPACE/$PREFIX/bin/$PYNAME";
PIP="$WORKSPACE/$PREFIX/bin/pip$PYVER";
TOX="$WORKSPACE/$PREFIX/bin/tox";
TOX2="$HOME/.local/bin/tox"


# Set up requested python environment.
if [ $PYIMPL == 'cpy' ]; then
    if [ ! -x "$PYTHON" ]; then
      (
        mkdir -p .data; cd .data;

        wget -ct0 $CPYTHON_URL_BASE/$FN;
        tar xf $(basename $FN);
        cd "$PREFIX";
        if [ ! -f "Makefile" ]; then
            ./configure --prefix="$WORKSPACE/$PREFIX" --without-pydebug --with-ensurepip;
        fi

        $MAKE && make install;
      );
    fi;

    export PATH="$WORKSPACE/$PREFIX/bin":"$PATH";

elif [ $PYIMPL == 'jyt' ]; then
    if [ ! -x "$PYTHON" ]; then
      (
        mkdir -p .data; cd .data;

        FILE=$(basename $FN);
        wget -O $FILE -ct0 "$JYTHON_URL_BASE/$FN";
        java -jar $FILE -s -d "$WORKSPACE/$PREFIX"

      );
    fi

elif [ $PYIMPL == 'ipy' ]; then
    # Set up Mono first
    # See: http://www.mono-project.com/Compiling_Mono_From_Tarball
    if [ ! -x "$XBUILD" ]; then
      (
        mkdir -p .data; cd .data;

        wget -ct0 http://download.mono-project.com/sources/mono/mono-$MONOVER.tar.bz2
        tar xf mono-$MONOVER.tar.bz2;
        cd mono-$MONOVER;
        ./configure --prefix=$WORKSPACE/mono-$MONOVER;
        $MAKE && make install;
      );
    fi

    # Set up IronPython
    # See: https://github.com/IronLanguages/main/wiki/Building#the-mono-runtime
    if [ ! -x "$PYTHON" ]; then
      (
        mkdir -p .data; cd .data;
        export PATH="$(dirname "$XBUILD"):$PATH"

        wget -ct0 "$IRONPYTHON_URL_BASE/$FN";
        unzip -q "$FN";
        cd "main-$PREFIX";

        $XBUILD /p:Configuration=Release Solutions/IronPython.sln || exit 1

        mkdir -p "$(dirname "$PYTHON")";
        echo 'mono "$PWD/bin/Release/ir.exe" "${@}"' > $PYTHON;
        chmod +x $PYTHON;
      ) || exit 1;
    fi;

fi;


# Set up pip
$PYTHON -m ensurepip --upgrade || exit 10;

# Set up tox
if [ ! -x "$TOX" ]; then
   $PIP install tox || exit 11;
fi;


set

"$PIP" install cython || exit 12

if [ "$PYVER" == "2.7" ]; then
    "$PIP" install numpy\<1.16.99 || exit 13;
    "$PIP" install -rrequirements/test_requirements_py27.txt || exit 14;

else
    "$PIP" install numpy || exit 15;
    "$PIP" install -rrequirements/test_requirements.txt || exit 16;

fi

[ -e .coverage ] && rm -v .coverage
[ -e .coverage ] && rm -v coverage.xml

export PYTHONHASHSEED=0

# ignore return value -- result information is in the produced xml files
"$PYTHON" setup.py test || true;
