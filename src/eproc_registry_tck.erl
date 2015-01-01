%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%
%%  "Technology Compatibility Kit" for `eproc_registry` implementations.
%%  This module contains testcases, that should be valid for all the
%%  `eproc_registry` implementations. The testcases are prepared to be
%%  used with the Common Test framework.
%%  See `eproc_reg_gproc_SUITE` for an example of using it.
%%
-module(eproc_registry_tck).
-export([all/0]).
-export([
    test_something/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%
%%
all() -> [
        test_something
    ].


%%
%%
%%
registry(Config) ->
    proplists:get_value(registry, Config).



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  TODO: Implement test cases.
%%
test_something(Config) ->
    _Registry = registry(Config),
    ok.


