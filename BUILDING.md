

Main Makefile targets
========================================

After the code was checked out (or when dependencies were updated):

    make deps

To compile the code:

    make

To run unit tests:

    make test

To run integration tests:

    make itest


Testing
========================================

The following is a command example for invoking particular unit test suite:

    env ERL_AFLAGS='-config test/sys' rebar eunit skip_deps=true verbose=1 suites=eproc_fsm


