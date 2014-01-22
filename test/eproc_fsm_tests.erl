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
%%
%%
unlink_kill(PID) ->
    true = unlink(PID),
    true = exit(PID, normal),
    ok.


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
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, add_instance, fun
        (_StoreRef, #instance{status = running, group = 17,  name = create_test, opts = [{n1, v1}]}) -> {ok, iid1};
        (_StoreRef, #instance{status = running, group = new, name = undefined,   opts = []        }) -> {ok, iid2}
    end),
    {ok, {inst, iid1}} = eproc_fsm:create(eproc_fsm__void, {}, [{group, 17}, {name, create_test}, {n1, v1}]),
    {ok, {inst, iid2}} = eproc_fsm:create(eproc_fsm__void, {}, []),
    ?assertEqual(2, meck:num_calls(eproc_store, add_instance, '_')),
    ?assertEqual(2, meck:num_calls(eproc_fsm__void, init, [{}])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]).


%%
%%  Check if initial state if stored properly.
%%
create_state_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void),
    ok = meck:expect(eproc_store, add_instance, fun
        (_StoreRef, #instance{args = {a, b}, init = {state, a, b}}) -> {ok, iid1}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun ({A, B}) -> {ok, {state, A, B}} end),
    {ok, {inst, iid1}} = eproc_fsm:create(eproc_fsm__void, {a, b}, []),
    ?assertEqual(1, meck:num_calls(eproc_store, add_instance, '_')),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, init, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]).



%%
%%  Check if new process can be started by instance id.
%%
start_link_by_inst_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, ['_', '_'])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if new process can be started by name.
%%
start_link_by_name_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {name, N = start_link_by_name_test}) ->
            {ok, #instance{
                id = 100, group = 200, name = N, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    {ok, PID} = eproc_fsm:start_link({name, start_link_by_name_test}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, ['_', '_'])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


% TODO: Assert the following
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


