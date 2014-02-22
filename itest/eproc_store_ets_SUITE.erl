%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
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
%%  Test cases for `eproc_store_ets`.
%%
-module(eproc_store_ets_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_add_instance/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").

%%
%%
%%
all() ->
    eproc_store_TCK:all().

%%
%%
%%
init_per_suite(Config) ->
    {ok, PID} = eproc_store_ets:start_link({local, eproc_store_ets_SUITE}),
    {ok, Store} = eproc_store:ref(eproc_store_ets, undefined),
    unlink(PID),
    [{store, Store}, {store_pid, PID} | Config].

%%
%%
%%
end_per_suite(Config) ->
    exit(proplists:get_value(store_pid, Config), kill),
    ok.


%% =============================================================================
%%  Testcases.
%% =============================================================================

test_add_instance(Config) ->
    eproc_store_TCK:test_add_instance(Config).


