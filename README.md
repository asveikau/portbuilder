# portbuilder.sh

This script automates building FreeBSD packages where their configuration options have been customized via `/var/db/ports` (`make config`) or `make.conf`.  It will scan both of these locations to see what has been built before, and try to build those.

I came to this idea when I realized how much work `poudriere` does building dependencies and how much space that work takes on disk.  In contrast, this script tries to fetch build dependencies with `pkg` and therefore only tries to build.

## Usage

Should be more or less automatic.  Running the script will:

* Update ports tree with `portsnap`
* Update packages with `pkg`.  Needed so that we don't build ports that link against dependencies that are no longer available.  [Got bit by that issue a few times].
* Install build dependencies with `pkg`.
* Build the ports.
* Copy packages into `./ports`.
