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
%%  Test cases for `eproc_store_ets`.
%%
-module(eproc_store_ets_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    eproc_store_core_test_unnamed_instance/1,
    eproc_store_core_test_named_instance/1,
    eproc_store_core_test_suspend_resume/1,
    eproc_store_core_test_add_transition/1,
    eproc_store_core_test_resolve_msg_dst/1,
    eproc_store_core_test_load_running/1,
    eproc_store_core_test_get_state/1,
    eproc_store_core_test_attrs/1,
    eproc_store_router_test_attrs/1,
    eproc_store_meta_test_attrs/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").

%%
%%
%%
all() ->
    lists:append([
        eproc_store_tck:testcases(core),
        eproc_store_tck:testcases(router),
        eproc_store_tck:testcases(meta)
    ]).

%%
%%
%%
init_per_suite(Config) ->
    {ok, PID} = eproc_store_ets:start_link({local, eproc_store_ets_SUITE}),
    {ok, Store} = eproc_store_ets:ref(),
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

-define(MAP_TCK_TEST(Name), Name(Config) -> eproc_store_tck:Name(Config)).

?MAP_TCK_TEST(eproc_store_core_test_unnamed_instance).
?MAP_TCK_TEST(eproc_store_core_test_named_instance).
?MAP_TCK_TEST(eproc_store_core_test_suspend_resume).
?MAP_TCK_TEST(eproc_store_core_test_add_transition).
?MAP_TCK_TEST(eproc_store_core_test_resolve_msg_dst).
?MAP_TCK_TEST(eproc_store_core_test_load_running).
?MAP_TCK_TEST(eproc_store_core_test_get_state).
?MAP_TCK_TEST(eproc_store_core_test_attrs).
?MAP_TCK_TEST(eproc_store_router_test_attrs).
?MAP_TCK_TEST(eproc_store_meta_test_attrs).


