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
%%  "Technology Compatibility Kit" for `eproc_store` implementations.
%%  This module contains testcases, that should be valid for all the
%%  `eproc_store` implementations. The testcases are prepared to be
%%  used with the Common Test framework.
%%  See `eproc_store_ets_SUITE` for an example of using it.
%%
-module(eproc_store_tck).
-export([testcases/1]).
-export([
    eproc_store_core_test_unnamed_instance/1,
    eproc_store_core_test_named_instance/1,
    eproc_store_core_test_suspend_resume/1,
    eproc_store_core_test_add_transition/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%
%%
testcases(core) -> [
    eproc_store_core_test_unnamed_instance,
    eproc_store_core_test_named_instance,
    eproc_store_core_test_suspend_resume,
    eproc_store_core_test_add_transition
    ];

testcases(router) -> [
    ];

testcases(meta) -> [
    ].


%%
%%
%%
store(Config) ->
    proplists:get_value(store, Config).


%%
%%  Provides default values.
%%
inst_value() ->
    #instance{
        id = undefined,
        group = new,
        name = undefined,
        module = some_fsm,
        args = [arg1],
        opts = [{o, p}],
        init = {state, a, b},
        status = running,
        created = erlang:now(),
        terminated = undefined,
        archived = undefined,
        transitions = undefined
    }.



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Check if the following functions work:
%%
%%    * add_instance(unnamed), w/wo group.
%%    * get_instance(iid), header.
%%    * load_instance(iid).
%%    * set_instance_killed(iid).
%%
%%  TODO:
%%
%%    * Suspend.
%%    * Resume.
%%    * Add transition.
%%    * Add transition.
%%    * Suspend.
%%    * Resume.
%%    * Suspend.
%%    * Resume.
%%    * Suspend.
%%
eproc_store_core_test_unnamed_instance(Config) ->
    Store = store(Config),
    %%  Add unnamed process with new group.
    %%  and second, to check if they are not interferring.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{group = new}),
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{group = 897}),
    true = undefined =/= IID1,
    true = undefined =/= IID2,
    true = IID1 =/= IID2,
    %%  Try to get instance headers.
    {ok, Inst1 = #instance{id = IID1, group = GRP1}} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2 = #instance{id = IID2, group = GRP2}} = eproc_store:get_instance(Store, {inst, IID2}, header),
    Inst1 = Inst#instance{id = IID1, group = GRP1},
    Inst2 = Inst#instance{id = IID2, group = GRP2},
    false = is_atom(GRP1),
    897 = GRP2,
    %%  Try to load instance data.
    {ok, LoadedInst = #instance{id = IID1, group = GRP1}} = eproc_store:load_instance(Store, {inst, IID1}),
    LoadedInst = Inst#instance{id = IID1, group = GRP1, transitions = []},
    %%  Kill created instances.
    {ok, IID1} = eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}),
    {ok, IID1} = eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}),
    {ok, IID2} = eproc_store:set_instance_killed(Store, {inst, IID2}, #user_action{}),
    {error, not_found} = eproc_store:set_instance_killed(Store, {inst, some}, #user_action{}),
    {ok, #instance{
        id = IID1,
        group = GRP1,
        status = killed,
        terminated = {_, _, _},
        term_reason = #user_action{}}
    } = eproc_store:get_instance(Store, {inst, IID1}, header),
    ok.


%%
%%  Check if the following functions work:
%%
%%    * add_instance(name), w/wo group.
%%    * get_instance(name), header.
%%    * load_instance(name).
%%    * set_instance_killed(name).
%%
%%  Scenario:
%%
%%    * Add instance with unique name.
%%    * Add another instance with unique name.
%%    * Add another instance with same name.
%%    * Add an instance with the name of already killed FSM.
%%
eproc_store_core_test_named_instance(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1}  = eproc_store:add_instance(Store, Inst#instance{group = new, name = test_named_instance_a}),
    {ok, IID2}  = eproc_store:add_instance(Store, Inst#instance{group = 897, name = test_named_instance_b}),
    {error, bad_name} = eproc_store:add_instance(Store, Inst#instance{group = 897, name = test_named_instance_b}),
    true = undefined =/= IID1,
    true = undefined =/= IID2,
    true = IID1 =/= IID2,
    %%  Try to get instance headers by IID and by name.
    {ok, Inst1 = #instance{id = IID1, group = GRP1}} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2 = #instance{id = IID2, group = GRP2}} = eproc_store:get_instance(Store, {inst, IID2}, header),
    {error, not_found}  = eproc_store:get_instance(Store, {inst, some}, header),
    {ok, Inst1}         = eproc_store:get_instance(Store, {name, test_named_instance_a}, header),
    {ok, Inst2}         = eproc_store:get_instance(Store, {name, test_named_instance_b}, header),
    {error, not_found}  = eproc_store:get_instance(Store, {name, test_named_instance_c}, header),
    Inst1 = Inst#instance{id = IID1, group = GRP1, name = test_named_instance_a},
    Inst2 = Inst#instance{id = IID2, group = GRP2, name = test_named_instance_b},
    false = is_atom(GRP1),
    897 = GRP2,
    %%  Try to load instance data.
    {ok, LoadedInst = #instance{id = IID1, group = GRP1}} = eproc_store:load_instance(Store, {name, test_named_instance_a}),
    LoadedInst = Inst#instance{id = IID1, group = GRP1, name = test_named_instance_a, transitions = []},
    %%  Kill created instances.
    {ok, IID1}         = eproc_store:set_instance_killed(Store, {name, test_named_instance_a}, #user_action{}),
    {error, not_found} = eproc_store:set_instance_killed(Store, {name, test_named_instance_a}, #user_action{}),
    {ok, IID2}         = eproc_store:set_instance_killed(Store, {name, test_named_instance_b}, #user_action{}),
    {error, not_found} = eproc_store:set_instance_killed(Store, {name, test_named_instance_v}, #user_action{}),
    {ok, #instance{
        id = IID1,
        group = GRP1,
        status = killed,
        terminated = {_, _, _},
        term_reason = #user_action{}}
    } = eproc_store:get_instance(Store, {inst, IID1}, header),
    %%  Names can be reused, after FSM termination.
    {ok, IID3} = eproc_store:add_instance(Store, Inst#instance{group = new, name = test_named_instance_a}),
    {ok, IID3} = eproc_store:set_instance_killed(Store, {name, test_named_instance_a}, #user_action{}),
    true = IID3 =/= IID1,
    ok.


%%
%%  TODO:.
%%
eproc_store_core_test_suspend_resume(_Config) ->
    throw(todo).


%%
%%  TODO:.for terminated FSM.
%%
eproc_store_core_test_add_transition(_Config) ->
    throw(todo).


