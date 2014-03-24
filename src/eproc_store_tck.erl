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
    eproc_store_core_test_add_transition/1,
    eproc_store_core_test_load_running/1
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
    eproc_store_core_test_add_transition,
    eproc_store_core_test_load_running
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
        start_spec = undefined,
        status = running,
        created = erlang:now(),
        terminated = undefined,
        archived = undefined,
        state = #inst_state{
            inst_id = undefined,
            trn_nr = 0,
            sname = [],
            sdata = {state, a, b},
            attr_last_id = 0,
            attrs_active = [],
            interrupt = undefined
        },
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
eproc_store_core_test_unnamed_instance(Config) ->
    Store = store(Config),
    %%  Add unnamed process with new group.
    %%  and second, to check if they are not interferring.
    Inst = #instance{state = State} = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{group = new}),
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{group = 897}),
    true = undefined =/= IID1,
    true = undefined =/= IID2,
    true = IID1 =/= IID2,
    %%  Try to get instance headers.
    {ok, Inst1 = #instance{id = IID1, group = GRP1}} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2 = #instance{id = IID2, group = GRP2}} = eproc_store:get_instance(Store, {inst, IID2}, header),
    Inst1 = Inst#instance{id = IID1, group = GRP1, state = undefined},
    Inst2 = Inst#instance{id = IID2, group = GRP2, state = undefined},
    false = is_atom(GRP1),
    897 = GRP2,
    %%  Try to load instance data.
    {ok, LoadedInst = #instance{id = IID1, group = GRP1}} = eproc_store:load_instance(Store, {inst, IID1}),
    LoadedInst = Inst#instance{id = IID1, group = GRP1, state = State#inst_state{inst_id = IID1}},
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
    Inst = #instance{state = State} = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{group = new, name = test_named_instance_a}),
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{group = 897, name = test_named_instance_b}),
    {error, bad_name} = eproc_store:add_instance(Store, Inst#instance{group = 897, name = test_named_instance_b}),
    true = undefined =/= IID1,
    true = undefined =/= IID2,
    true = IID1 =/= IID2,
    %%  Try to get instance headers by IID and by name.
    {ok, Inst1 = #instance{id = IID1, group = GRP1, state = undefined}} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2 = #instance{id = IID2, group = GRP2, state = undefined}} = eproc_store:get_instance(Store, {inst, IID2}, header),
    {error, not_found}  = eproc_store:get_instance(Store, {inst, some}, header),
    {ok, Inst1}         = eproc_store:get_instance(Store, {name, test_named_instance_a}, header),
    {ok, Inst2}         = eproc_store:get_instance(Store, {name, test_named_instance_b}, header),
    {error, not_found}  = eproc_store:get_instance(Store, {name, test_named_instance_c}, header),
    Inst1 = Inst#instance{id = IID1, group = GRP1, name = test_named_instance_a, state = undefined},
    Inst2 = Inst#instance{id = IID2, group = GRP2, name = test_named_instance_b, state = undefined},
    false = is_atom(GRP1),
    897 = GRP2,
    %%  Try to load instance data.
    {ok, LoadedInst = #instance{id = IID1, group = GRP1}} = eproc_store:load_instance(Store, {name, test_named_instance_a}),
    LoadedInst = Inst#instance{id = IID1, group = GRP1, name = test_named_instance_a, state = State#inst_state{inst_id = IID1}},
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
%%  Check if suspend/resume functionality works:
%%
%%    * set_instance_suspended/*
%%    * set_instance_resuming/*
%%        * StateAction :: unchanged | retry_last | {set, NewStateName, NewStateData, ResumeScript}
%%        * InstStatus
%%    * set_instance_resumed/*
%%
%%  Also checks, if kill has no effect on second invocation.
%%
eproc_store_core_test_suspend_resume(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, []}}),
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{start_spec = {mfa,{a,b,[]}}}),
    {ok, IID3} = eproc_store:add_instance(Store, Inst#instance{}),
    {ok, IID4} = eproc_store:add_instance(Store, Inst#instance{}),
    %%  Suspend them.
    {error, not_found}  = eproc_store:set_instance_suspended(Store, {inst, some}, #user_action{}),  %% Inst not found
    {ok, IID1}          = eproc_store:set_instance_suspended(Store, {inst, IID1}, #user_action{}),  %% Ok, suspend.
    {ok, IID2}          = eproc_store:set_instance_suspended(Store, {inst, IID2}, #user_action{}),  %% Ok, suspend.
    {ok, IID2}          = eproc_store:set_instance_suspended(Store, {inst, IID2}, #user_action{}),  %% Already suspended
    {ok, IID3}          = eproc_store:set_instance_killed(Store, {inst, IID3}, #user_action{}),
    {error, terminated} = eproc_store:set_instance_suspended(Store, {inst, IID3}, #user_action{}),  %% Already terminated
    {ok, Inst1Suspended} = eproc_store:get_instance(Store, {inst, IID1}, current),
    {ok, Inst2Suspended} = eproc_store:get_instance(Store, {inst, IID2}, current),
    #instance{status = suspended, state = #inst_state{interrupt = #interrupt{}}} = Inst1Suspended,
    #instance{status = suspended, state = #inst_state{interrupt = #interrupt{}}} = Inst2Suspended,
    %%  Mark them resuming
    {error, not_found}         = eproc_store:set_instance_resuming(Store, {inst, some}, unchanged, #user_action{}),   %% Inst not found.
    {ok, IID1, {default, []}}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Ok, resumed wo state change.
    {ok, IID1, {default, []}}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Already resuming.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, retry_last, #user_action{}),           %% Ok, resumed with last state wo change.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, {set, [s1], d1, []}, #user_action{}),  %% Ok, resumed with state change.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, {set, [s2], d2, []}, #user_action{}),  %% Ok, resumed with state change.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, retry_last, #user_action{}),           %% Ok, resumed with last change.
    {ok, Inst1Resuming} = eproc_store:get_instance(Store, {inst, IID1}, current),
    {ok, Inst2Resuming} = eproc_store:get_instance(Store, {inst, IID2}, current),
    #instance{status = resuming, state = #inst_state{interrupt = #interrupt{}}} = Inst1Resuming,
    #instance{status = resuming, state = #inst_state{interrupt = #interrupt{}}} = Inst2Resuming,
    %%  Mark them resumed
    ok = eproc_store:set_instance_resumed(Store, IID1, 2),
    ok = eproc_store:set_instance_resumed(Store, IID1, 2),
    {error, running}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Try resume running FSM
    {ok, Inst1Resumed} = eproc_store:get_instance(Store, {inst, IID1}, current),
    #instance{status = running, state = #inst_state{interrupt = undefined}} = Inst1Resumed,
    %%  Kill them.
    {ok, Inst3Killed} = eproc_store:get_instance(Store, {inst, IID3}, current),
    {ok, IID1} = eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}),
    {ok, IID2} = eproc_store:set_instance_killed(Store, {inst, IID2}, #user_action{}),
    {ok, IID3} = eproc_store:set_instance_killed(Store, {inst, IID3}, #user_action{}), %% Kill it second time.
    {ok, IID4} = eproc_store:set_instance_killed(Store, {inst, IID4}, #user_action{}),
    {ok, Inst3Killed} = eproc_store:get_instance(Store, {inst, IID3}, current),
    {error, terminated}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Try resume terminated FSM
    ok.


%%
%%  Checks, if `add_transition` works including the following cases:
%%    * Ordinary transition
%%    * Messages and msg refs.
%%
eproc_store_core_test_add_transition(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst),
    %%
    %%  Add ordinary transition
    Trn1 = #transition{
        inst_id = IID1,
        number = 1,
        sname = [s1],
        sdata = d1,
        timestamp = erlang:now(),
        duration = 13,
        trigger_type = event,
        trigger_msg = #msg_ref{id = 1011, peer = {connector, some}},
        trigger_resp = #msg_ref{id = 1012, peer = {connector, some}},
        trn_messages = [#msg_ref{id = 1013, peer = {connector, some}}],
        attr_last_id = 1,
        attr_actions = [#attr_action{module = m, attr_id = 1, action = {create, undefined, [], some}}],
        inst_status = running,
        interrupts = undefined
    },
    Msg11 = #message{id = 1011, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m11},
    Msg12 = #message{id = 1012, sender = {connector, some}, receiver = {inst, IID1}, resp_to = 1011,      date = erlang:now(), body = m12},
    Msg13 = #message{id = 1013, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m13},
    {ok, IID1, 1} = eproc_store:add_transition(Store, Trn1, [Msg11, Msg12, Msg13]),
    {ok, #instance{status = running, state = #inst_state{
        inst_id = IID1, trn_nr = 1,
        sname = [s1], sdata = d1,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add another ordinary transition
    Trn2 = Trn1#transition{
        number = 2,
        sname = [s2],
        sdata = d2,
        trigger_msg = #msg_ref{id = 1021, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = []
    },
    Msg21 = #message{id = 1021, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m21},
    {ok, IID1, 2} = eproc_store:add_transition(Store, Trn2, [Msg21]),
    {ok, #instance{status = running, state = #inst_state{
        inst_id = IID1, trn_nr = 2,
        sname = [s2], sdata = d2,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Suspend by transition.
    Trn3 = Trn1#transition{
        number = 3,
        sname = [s3],
        sdata = d3,
        trigger_msg = #msg_ref{id = 1031, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = suspended,
        interrupts = [#interrupt{reason = {fault, some_reason}}]
    },
    Msg31 = #message{id = 1031, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m31},
    {ok, IID1, 3} = eproc_store:add_transition(Store, Trn3, [Msg31]),
    {ok, #instance{status = suspended, state = #inst_state{
        inst_id = IID1, trn_nr = 3,
        sname = [s3], sdata = d3,
        attr_last_id = 1, attrs_active = [_],
        interrupt = #interrupt{
            inst_id = IID1,
            trn_nr = undefined,
            status = active,
            suspended = {_, _, _},
            reason = {fault, some_reason},
            resumes = []
        }
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Resume with transition.
    {ok, IID1, _}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    {ok, IID1, _}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    {ok, IID1, _}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    Trn4 = Trn1#transition{
        number = 4,
        sname = [s4],
        sdata = d4,
        trigger_msg = #msg_ref{id = 1041, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg41 = #message{id = 1041, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m41},
    {ok, IID1, 4} = eproc_store:add_transition(Store, Trn4, [Msg41]),
    {ok, #instance{status = running, state = #inst_state{
        inst_id = IID1, trn_nr = 4,
        sname = [s4], sdata = d4,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Terminate FSM.
    Trn5 = Trn1#transition{
        number = 5,
        sname = [s5],
        sdata = d5,
        trigger_msg = #msg_ref{id = 1051, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = completed,
        interrupts = undefined
    },
    Msg51 = #message{id = 1051, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m51},
    {ok, IID1, 5} = eproc_store:add_transition(Store, Trn5, [Msg51]),
    {ok, #instance{status = completed, state = #inst_state{
        inst_id = IID1, trn_nr = 5,
        sname = [s5], sdata = d5,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add transition to the terminated FSM.
    Trn6 = Trn1#transition{
        number = 6,
        sname = [s6],
        sdata = d6,
        trigger_msg = #msg_ref{id = 1061, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg61 = #message{id = 1061, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m61},
    {error, terminated} = eproc_store:add_transition(Store, Trn6, [Msg61]),
    {ok, #instance{status = completed, state = #inst_state{
        inst_id = IID1, trn_nr = 5,
        sname = [s5], sdata = d5,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    ok.


%%
%%  Check, if load_running works.
%%
eproc_store_core_test_load_running(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [1]}}),   % Resuming
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [2]}}),   % Suspended
    {ok, IID3} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [3]}}),   % Killed
    {ok, IID4} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [4]}}),
    {ok, IID5} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [5]}}),
    {ok, IID1} = eproc_store:set_instance_suspended(Store, {inst, IID1}, #user_action{}),
    {ok, IID2} = eproc_store:set_instance_suspended(Store, {inst, IID2}, #user_action{}),
    {ok, IID1, {default, [1]}}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    {ok, IID3} = eproc_store:set_instance_killed(Store, {inst, IID3}, #user_action{}),
    {ok, Running} = eproc_store:load_running(Store, fun (_, _) -> true end),
    [  ] = [ ok || {{inst, I}, {default, [1]}} <- Running, I =:= IID1 ],
    [  ] = [ ok || {{inst, I}, {default, [2]}} <- Running, I =:= IID2 ],
    [  ] = [ ok || {{inst, I}, {default, [3]}} <- Running, I =:= IID3 ],
    [ok] = [ ok || {{inst, I}, {default, [4]}} <- Running, I =:= IID4 ],
    [ok] = [ ok || {{inst, I}, {default, [5]}} <- Running, I =:= IID5 ],
    ok.


