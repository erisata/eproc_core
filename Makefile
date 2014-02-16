#/--------------------------------------------------------------------
#| Copyright 2013-2014 Erisata, UAB (Ltd.)
#|
#| Licensed under the Apache License, Version 2.0 (the "License");
#| you may not use this file except in compliance with the License.
#| You may obtain a copy of the License at
#|
#|     http://www.apache.org/licenses/LICENSE-2.0
#|
#| Unless required by applicable law or agreed to in writing, software
#| distributed under the License is distributed on an "AS IS" BASIS,
#| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#| See the License for the specific language governing permissions and
#| limitations under the License.
#\--------------------------------------------------------------------
REBAR=rebar


all: compile-all

deps:
	$(REBAR) get-deps

compile:
	$(REBAR) compile skip_deps=true

compile-all:
	$(REBAR) compile

check: test itest

test: compile
	env ERL_AFLAGS='-config test/sys' $(REBAR) eunit skip_deps=true verbose=1

itest: compile
	$(REBAR) ct skip_deps=true

clean:
	$(REBAR) clean skip_deps=true

clean-all:
	$(REBAR) clean
	rm -f itest/*.beam

.PHONY: all deps compile compile-all check test itest clean clean-all

