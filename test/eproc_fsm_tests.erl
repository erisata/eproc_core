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


%% TODO: Check if `check_state/1` works.
%% TODO: Check if `check_next_state/1` works.


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
%%  Check if `send_event/*` works with final_state from the initial state.
%%
send_event_final_state_from_init_test() ->
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
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{number = TrnNr}, [#message{}]) ->
            #transition{
                inst_id      = 100,
                number       = 1,
                sname        = [done],
                sdata        = {state, a},
                timestamp    = {_, _, _},
                duration     = Duration,
                trigger_type = event,
                trigger_msg  = #msg_ref{id = {100, 1, 0}, peer = {test, test}},
                trigger_resp = undefined,
                trn_messages = [],
                attr_last_id = 0,
                attr_actions = [],
                attrs_active = undefined,
                inst_status  = done,
                inst_suspend = undefined
            } = Transition,
            ?assert(is_integer(Duration)),
            ?assert(Duration >= 0),
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, done, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[], {event, done}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with final_state from an ordinary state.
%%
send_event_final_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = done
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, close, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, close}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [closed]}, '_'])),
    ?assertEqual(2, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with next_state from the initial state.
%%
send_event_next_state_from_init_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 1}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, reset, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[], {event, reset}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {entry, []}, '_'])),
    ?assertEqual(2, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with next_state from an ordinary state.
%%
send_event_next_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, flip, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, flip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [decrementing]}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[decrementing], {entry, [incrementing]}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` crashes with same_state from the initial state.
%%
send_event_same_state_from_init_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{number = TrnNr}, _Messages) ->
            {ok, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([], {event, skip}, StateData) ->
            {same_state, StateData}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    unlink(PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[], {event, skip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(0, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]).


%%
%%  Check if `send_event/*` works with same_state from an ordinary state.
%%
send_event_same_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, skip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` craches if reply_* is returned from the state transition.
%%
send_event_reply_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, #transition{number = TrnNr}, _Messages) ->
            {ok, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {event, get}, StateData) ->
            {reply_next, bad, [decrementing], StateData}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    unlink(PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, get, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, get}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(0, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]).


%%
%%  Check if runtime state is not stored to the DB.
%%
send_event_save_runtime_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], init = {state, a, this_is_empty}, status = running,
                created = erlang:now(), transitions = []
            }}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([], {state, a, this_is_empty}) ->
            {ok, 3, not_empty_at_runtime}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, #transition{number = TrnNr, sdata = {state, a, this_is_empty}}, [#message{}]) ->
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, done, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[], {event, done}, {state, a, not_empty_at_runtime}])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void])),
    ok = meck:unload([eproc_store, eproc_fsm__void]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` handles attributes correctly.
%%
send_event_handle_attrs_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm_attr, [passthrough]),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, flip, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr, transition_start, '_')),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr, transition_end, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm_attr, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm_attr, eproc_fsm__seq]),
    ok = unlink_kill(PID).



% TODO: Check if `send_event/*` works, assert the following:
%   * Check if process is unregistered from the restart manager.



%%
%%  Check if `sync_send_event/*` works with reply_final from an ordinary state.
%%
sync_send_event_final_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = #msg_ref{id = {InstId, TrnNr, 1}, peer = {test, test}},
                inst_status  = done
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, 5}, eproc_fsm:sync_send_event(PID, last, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', last}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [closed]}, '_'])),
    ?assertEqual(2, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `sync_send_event/*` works with reply_next from an ordinary state.
%%
sync_send_event_next_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = #msg_ref{id = {InstId, TrnNr, 1}, peer = {test, test}},
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, 5}, eproc_fsm:sync_send_event(PID, next, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', next}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [incrementing]}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {entry, [incrementing]}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `sync_send_event/*` works with reply_same from an ordinary state.
%%
sync_send_event_same_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = #msg_ref{id = {InstId, TrnNr, 1}, peer = {test, test}},
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, 5}, eproc_fsm:sync_send_event(PID, get, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', get}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if `sync_send_event/*` works with reply/*.
%%
sync_send_event_reply_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = {test, test}},
                trigger_resp = #msg_ref{id = {InstId, TrnNr, 1}, peer = {test, test}},
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {sync, From, get}, StateData) ->
            eproc_fsm:reply(From, {ok, something}),
            {same_state, StateData}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, something}, eproc_fsm:sync_send_event(PID, get, [{source, {test, test}}])),
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', get}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).


%%
%%  Check if unknown messages are forwarded to the callback module.
%%
unknown_message_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], init = {state, undefined}, status = running,
                created = erlang:now(), transitions = [#transition{
                    inst_id = 100, number = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_id = 0, attr_actions = [], attrs_active = []
                }]
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, Transition = #transition{inst_id = InstId, number = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = info,
                trigger_msg  = #msg_ref{id = {InstId, TrnNr, 0}, peer = undefined},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {info, some_unknown_message}, StateData) ->
            {same_state, StateData}
    end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    PID ! some_unknown_message,
    timer:sleep(100),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {info, some_unknown_message}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq])),
    ok = meck:unload([eproc_store, eproc_fsm__seq]),
    ok = unlink_kill(PID).




% TODO: Check if await/* works.

% TODO: Test handling of crashes in callbacks in sync and async calls.

% TODO: Check if send_create_event/* works.
% TODO: Check if sync_send_create_event/* works.
% TODO: Check if kill/* works.
% TODO: Check if suspend/* works.
% TODO: Check if resume/* works.
% TODO: Check if set_state/* works.

% TODO: Check if register_message/* works.
