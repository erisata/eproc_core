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
-module(eproc_fsm_tests).
-compile([{parse_transform, lager_transform}]).
-define(DEBUG, true).
-include_lib("eunit/include/eunit.hrl").
-include("eproc.hrl").


%%
%%  Configure application for tests.
%%  See also config in "test/sys.config" and its use in Makefile.
%%
application_setup() ->
    application:load(eproc_core),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_registry_gproc, []}),
    application:ensure_all_started(eproc_core).


%%
%%  Check if scope handing works.
%%
state_in_scope_test_() ->
    [
        ?_assert(true =:= eproc_fsm:state_in_scope([], [])),
        ?_assert(true =:= eproc_fsm:state_in_scope([a], [])),
        ?_assert(true =:= eproc_fsm:state_in_scope([a], [a])),
        ?_assert(true =:= eproc_fsm:state_in_scope([a, b], [a])),
        ?_assert(true =:= eproc_fsm:state_in_scope([a, b], [a, b])),
        ?_assert(true =:= eproc_fsm:state_in_scope([a, b], ['_', b])),
        ?_assert(true =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [a])),
        ?_assert(true =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{a, [], []}])),
        ?_assert(true =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{a, '_', '_'}])),
        ?_assert(true =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{a, [b], '_'}])),
        ?_assert(false =:= eproc_fsm:state_in_scope([], [a])),
        ?_assert(false =:= eproc_fsm:state_in_scope([a], [b])),
        ?_assert(false =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [b])),
        ?_assert(false =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{b}])),
        ?_assert(false =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{b, []}])),
        ?_assert(false =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{b, [], []}])),
        ?_assert(false =:= eproc_fsm:state_in_scope([{a, [b], [c]}], [{a, [c], []}]))
    ].


%%
%%  Test for eproc_fsm:create(Module, Args, Options)
%%
create_test() ->
    application_setup(),
    {ok, StoreRef} = eproc_store:ref(),
    ok = meck:new(eproc_fsm__void, [non_strict, passthrough]),
    {ok, {inst, _} = VoidIID1} = eproc_fsm:create(eproc_fsm__void, {}, [{group, 17}, {name, create_test}, {custom1, c1}]),
    {ok, {inst, _} = VoidIID2} = eproc_fsm:create(eproc_fsm__void, {}, []),
    {ok, Instance1} = eproc_store:get_instance(StoreRef, VoidIID1, []),
    {ok, Instance2} = eproc_store:get_instance(StoreRef, VoidIID2, []),
    ?assertEqual(running, Instance1#instance.status),
    ?assertEqual(running, Instance2#instance.status),
    ?assertEqual(17, Instance1#instance.group),
    ?assert(is_integer(Instance2#instance.group)),
    ?assertEqual(create_test, Instance1#instance.name),
    ?assertEqual(undefined,   Instance2#instance.name),
    ?assertEqual([{custom1, c1}], Instance1#instance.opts),
    ?assertEqual([],              Instance2#instance.opts),
    ?assertEqual(2, meck:num_calls(eproc_fsm__void, init, [{}])),
    ?assert(meck:validate(eproc_fsm__void)),
    ok = meck:unload(eproc_fsm__void).


%%
%%  Check if initial state if stored properly.
%%
create_state_test() ->
    application_setup(),
    {ok, StoreRef} = eproc_store:ref(),
    ok = meck:new(eproc_fsm__void),
    ok = meck:expect(eproc_fsm__void, init, fun ({A, B}) -> {ok, {state, A, B}} end),
    {ok, IID} = eproc_fsm:create(eproc_fsm__void, {a, b}, []),
    {ok, Inst} = eproc_store:get_instance(StoreRef, IID, []),
    ?assertEqual({a, b},        Inst#instance.args),
    ?assertEqual({state, a, b}, Inst#instance.init),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, init, '_')),
    ?assert(meck:validate(eproc_fsm__void)),
    ok = meck:unload(eproc_fsm__void).



%%
%%  Check if start_link/2-3 works.
%%
start_link_test() ->
    application_setup(),
    {ok, IID} = eproc_fsm:create(eproc_fsm__void, {}, []),
    {ok, PID} = eproc_fsm:start_link(IID, []),
    % TODO: Assert the following
    %   * Start by IID,
    %   * Start by Name
    %   * Start new instance.
    %       - Check StateData and StateName.
    %   * Restart existing instance.
    %       - Check StateData and StateName.
    %   * Start with FsmName specified.
    %   * Start with restart_delay option.
    %   * Start with all cases of register option.
    %   * Check if callback init/2 is invoked.
    %   * Check initialization of runtime state in init/2.
    %   * Check if callback code_change/3 is invoked with `state`.
    %   * Check if functions id/0, group/0, name/0 work.
    ok.

