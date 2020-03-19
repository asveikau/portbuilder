#!/bin/sh
# Script to automate building FreeBSD ports based on where you have modified
# config via /var/db/ports or /etc/make.conf.
#
# Copyright (c) 2020 Andrew Sveikauskas
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

MAKE=make
PORTSNAP=portsnap
PKG=pkg

PORTS_SRCDIR=/usr/ports
PORTS_DB=/var/db/ports
MAKE_CONF=/etc/make.conf

# Where to spit out files
OUT_DIR=./ports

# Some assumptions fail when /usr/ports is a symlink ...
PORTS_SRCDIR="`realpath "$PORTS_SRCDIR"`"

set -e -o pipefail

# Replaces slashes with underscores.
# This allows us to scan /var/db/ports or make.conf variables and convert to a
# path.
#
sanitize_port_names() {
   sed -e 's|_|/|'
}

# Same as above, but using a command arg for a single port
#
sanitize_port_name() {
   echo "$1" | sanitize_port_names
}

# Path inside ports build dir
#
port_src_dir() {
   portname="`sanitize_port_name "$1"`"
   echo "$PORTS_SRCDIR"/"$portname"
}

# Get the dependencies of a given port
#
build_depends() {
   $MAKE -C "`port_src_dir "$1"`" build-depends-list | sed -e 's|^'"$PORTS_SRCDIR"'/||'
}

# Some ports have a different package name than their directory. (eg.: devel/glib20)
# For this we will invoke make to print out the package name.  This started out as
# a feeble attempt to parse makefile variable declarations, but actually a few of them
# are highly complicated and depend on other variables, so let make do the real thing.
#
portname_filter() {
   while read port; do
      file="`port_src_dir $port`"/Makefile

      # There is a bug where we might represent
      # eg.: multimedia/v4l_linux
      # as:  multimedia/v4l/linux 
      # Should fix.  But for now work around.
      #
      [ -f "$file" ] || continue

      $MAKE -C "`port_src_dir $port`" ORIG_PORTNAME="$port" -f - portbuilder-print-name << "EOF"
include Makefile 
PORTNAME?=$(ORIG_PORTNAME)
portbuilder-print-name:
	@echo $(PKGNAMEPREFIX)$(PORTNAME)$(PKGNAMESUFFIX)
EOF
   done
}

# Some ports don't have prebuilt package
#
ignore_empty_rquery() {
   while read port; do
      pkg rquery -I "$port" > /dev/null 2>&1 && echo "$port" || true
   done
}

# List ports we have done "make config" on or customized via make.conf.
#
modified_ports() {
   ((cd "$PORTS_DB" && ls -d * || true); \
    (sed -e 's/#.*//' < "$MAKE_CONF" || true) | \
       awk '/([^[:space:]]*)_(UNSET|SET)[[:space:]]*(\+=|=).*$/ { 
           split($1, a, /_(UNSET|SET)/);
           sub(/^[[:space:]]*/,"",a[1]);
           print a[1]; }' \
   ) 2>/dev/null | sanitize_port_names | sort | uniq
}

to_build="`modified_ports`"

#
# First ensure ports tree is up to date.
#

$PORTSNAP fetch
$PORTSNAP update

#
# Install build dependencies using pkg
#

$PKG update
$PKG upgrade

depends="`(for port in $to_build; do
   build_depends "$port"
done)|sort|uniq|grep -v /pkg$|portname_filter|ignore_empty_rquery`"

if [ "$depends" != "" ]; then
   $PKG install $depends
fi

#
# Now we build the packages.
#

export BATCH=yes

mkdir -p "$OUT_DIR"

for port in $to_build; do
   echo Building "$port" ...
   srcdir="`port_src_dir "$port"`"
   $MAKE -C "$srcdir" clean
   $MAKE -C "$srcdir" package
   cp "$srcdir"/work/pkg/* "$OUT_DIR"/
done

