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
%%  Helper function.
%%
unlink_kill(PIDs) when is_list(PIDs) ->
    lists:foreach(fun unlink_kill/1, PIDs);

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
%%  Also checks, if attributes initialized.
%%
start_link_new_by_inst_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm_attr, []),
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
    ok = meck:expect(eproc_fsm_attr, init, fun
        ([], 0, []) -> {ok, []}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm_attr, init, [[], 0, []])),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm_attr, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm_attr, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if new process can be started by name.
%%
start_link_new_by_name_test() ->
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
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if existing process can be restarted.
%%  Also checks, if attributes initialized.
%%
start_link_existing_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm_attr, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 100}) ->
            {ok, #instance{
                id = I, group = I, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = I, number = 1, sname = [some], sdata = {state, b},
                    attr_last_id = 2, attr_actions = [], attrs_active = [
                        #attribute{attr_id = 1},
                        #attribute{attr_id = 2}
                    ]
                }]
            }}
    end),
    ok = meck:expect(eproc_fsm_attr, init, fun
        ([some], 2, [A = #attribute{attr_id = 1}, B = #attribute{attr_id = 2}]) -> {ok, [{A, undefined}, {B, undefined}]}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm_attr, init, '_')),
    ?assert(meck:called(eproc_fsm__void, init, [[some], {state, b}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [some], {state, b}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm_attr, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm_attr, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if functions id/0, group/0, name/0 works in an FSM process.
%%
start_link_get_id_group_name_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([], {state, a}) ->
            ?assertEqual({ok, 1000}, eproc_fsm:id()),
            ?assertEqual({ok, 2000}, eproc_fsm:group()),
            ?assertEqual({ok, name}, eproc_fsm:name()),
            ok
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if runtime state initialization works.
%%  This will not theck, id runtime field is passed to other
%%  callbacks and not stored in DB. Other tests exists for that.
%%
start_link_init_runtime_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a, undefined}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([], {state, a, undefined}) ->
            {ok, 3, z}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a, undefined}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a, undefined}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check, if FSM can be started with standard process registration.
%%
start_link_fsmname_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    {ok, PID} = eproc_fsm:start_link({local, start_link_fsmname_test}, {inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(eproc_fsm:is_online(start_link_fsmname_test)),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if register option is handled properly.
%%  This test also checks, if registry is resolved.
%%
start_link_opts_register_test() ->
    GenInst = fun (I, N) -> #instance{
        id = I, group = I, name = N, module = eproc_fsm__void,
        args = {a}, opts = [], init = {state, a}, status = running,
        created = erlang:now(), transitions = []
    } end,
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_registry, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun
        () -> {ok, store}
    end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) -> {ok, GenInst(I, name0)};
        (store, {inst, I = 1001}) -> {ok, GenInst(I, name1)};
        (store, {inst, I = 1002}) -> {ok, GenInst(I, name2)};
        (store, {inst, I = 1003}) -> {ok, GenInst(I, name3)};
        (store, {inst, I = 1004}) -> {ok, GenInst(I, name4)}
    end),
    ok = meck:expect(eproc_registry, ref, fun
        () -> {ok, reg2}
    end),
    ok = meck:expect(eproc_registry, register_inst, fun
        (reg1, 1001) -> ok;
        (reg1, 1003) -> ok;
        (reg2, 1004) -> ok
    end),
    ok = meck:expect(eproc_registry, register_name, fun
        (reg1, 1002, name2) -> ok;
        (reg1, 1003, name3) -> ok;
        (reg2, 1004, name4) -> ok
    end),
    {ok, PID0a} = eproc_fsm:start_link({inst, 1000}, [{register, none}]), % Registry will be not used.
    {ok, PID0b} = eproc_fsm:start_link({inst, 1000}, [{register, none}, {registry, reg1}]),
    {ok, PID1}  = eproc_fsm:start_link({inst, 1001}, [{register, id},   {registry, reg1}]),
    {ok, PID2}  = eproc_fsm:start_link({inst, 1002}, [{register, name}, {registry, reg1}]),
    {ok, PID3}  = eproc_fsm:start_link({inst, 1003}, [{register, both}, {registry, reg1}]),
    {ok, PID4}  = eproc_fsm:start_link({inst, 1004}, [{register, both}]), % Will use default
    ?assert(eproc_fsm:is_online(PID0a)),
    ?assert(eproc_fsm:is_online(PID0b)),
    ?assert(eproc_fsm:is_online(PID1)),
    ?assert(eproc_fsm:is_online(PID2)),
    ?assert(eproc_fsm:is_online(PID3)),
    ?assert(eproc_fsm:is_online(PID4)),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_inst, [reg1, 1001])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_inst, [reg1, 1003])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_inst, [reg2, 1004])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_name, [reg1, 1002, name2])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_name, [reg1, 1003, name3])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_name, [reg2, 1004, name4])),
    ?assertEqual(1, meck:num_calls(eproc_registry, ref, [])),
    ?assert(meck:validate([eproc_store, eproc_registry, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_registry, eproc_fsm__void]),
    ok = unlink_kill([PID0a, PID0b, PID1, PID2, PID3, PID4]).


%%
%%  Check if restart options are handled properly.
%%  Also checks, if store is resolved from args.
%%
start_link_opts_restart_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_restart, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    ok = meck:expect(eproc_restart, restarted, fun
        ({eproc_fsm, 100}, [{delay, {const, 100}}]) -> ok;
        ({eproc_fsm, 100}, []) -> ok
    end),

    {ok, PID1} = eproc_fsm:start_link({inst, 100}, [{store, store}, {restart, [{delay, {const, 100}}]}]),
    {ok, PID2} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID1)),
    ?assert(eproc_fsm:is_online(PID2)),
    ?assertEqual(1, meck:num_calls(eproc_restart, restarted, [{eproc_fsm, 100}, [{delay, {const, 100}}]])),
    ?assertEqual(1, meck:num_calls(eproc_restart, restarted, [{eproc_fsm, 100}, []])),
    ?assert(meck:validate([eproc_store, eproc_restart, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_restart, eproc_fsm__void]),
    ok = unlink_kill([PID1, PID2]).


%%
%%  Check if `send_event/*` works with next_state.
%%
send_event_next_state_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, sender, event)),

    ?assert(meck:validate([eproc_store,eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).



% TODO: Check if `send_event/*` works, assert the following:
%   * Check if runtime field is passed to transition and not stored to DB.
%   * Check all transtion responses.
%   * Check if attributes handled properly.



% TODO: Check if sync_send_event/* and reply/* works.
% TODO: Check if await/* works.

% TODO: Check if send_create_event/* works.
% TODO: Check if sync_send_create_event/* works.
% TODO: Check if kill/* works.
% TODO: Check if suspend/* works.
% TODO: Check if resume/* works.
% TODO: Check if set_state/* works.

% TODO: Check if register_message/* works.
% TODO: Check if is_online/* works.
