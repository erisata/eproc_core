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
-export([all/0]).
-export([
    test_unnamed_instance/1,
    test_named_instance/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%
%%
all() -> [
        test_unnamed_instance,
        test_named_instance
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
%%    * get_instance(), header.
%%    * load_instance().
%%    * set_instance_killed().
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
test_unnamed_instance(Config) ->
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
    ok.


%%
%%    * get and non-existing instance.
%%    * Add Another instance with name.
%%    * Add Another instance with same name.
%%
%%
test_named_instance(_Config) ->
    ok.


