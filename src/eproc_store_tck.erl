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
    #instance{status = suspended, state = #inst_state{}} = Inst1Suspended,
    #instance{status = suspended, state = #inst_state{}} = Inst2Suspended,
    %%  Mark them resuming
    {error, not_found}         = eproc_store:set_instance_resuming(Store, {inst, some}, unchanged, #user_action{}),   %% Inst not found.
    {ok, IID1, {default, []}}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Ok, resumed wo state change.
    {ok, IID1, {default, []}}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Already resuming.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, retry_last, #user_action{}),           %% Ok, resumed with last state wo change.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, {set, [s1], d1, []}, #user_action{}),  %% Ok, resumed with state change.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, {set, [s2], d2, []}, #user_action{}),  %% Ok, resumed with state change.
    {ok, IID2, {mfa,{a,b,[]}}} = eproc_store:set_instance_resuming(Store, {inst, IID2}, retry_last, #user_action{}),           %% Ok, resumed with last change.
    {ok, Inst1Resumed} = eproc_store:get_instance(Store, {inst, IID1}, current),
    {ok, Inst2Resumed} = eproc_store:get_instance(Store, {inst, IID2}, current),
    #instance{status = resuming, state = #inst_state{}} = Inst1Resumed,
    #instance{status = resuming, state = #inst_state{}} = Inst2Resumed,
    %%  Mark them resumed
    ok = eproc_store:set_instance_resumed(Store, IID1, 2),
    ok = eproc_store:set_instance_resumed(Store, IID1, 2),
    {error, running}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Try resume running FSM
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
%%    * TODO: Suspend,
%%    * TODO: Resume
%%    * TODO: Terminate
%%    * TODO:.for terminated FSM.
%%
eproc_store_core_test_add_transition(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst),
    %%  Add transitions.
    Trn1 = #transition{
        inst_id = IID1,
        number = 1,
        sname = [s1],
        sdata = d1,
        timestamp = erlang:now(),
        duration = 13,
        trigger_type = event,
        trigger_msg = #msg_ref{id = 1001, peer = {connector, some}},
        trigger_resp = #msg_ref{id = 1002, peer = {connector, some}},
        trn_messages = [#msg_ref{id = 1003, peer = {connector, some}}],
        attr_last_id = 1,
        attr_actions = [#attr_action{module = m, attr_id = 1, action = {create, undefined, [], some}}],
        inst_status = running,
        interrupts = undefined
    },
    Trn2 = Trn1#transition{
        number = 2,
        sname = [s2],
        sdata = d2,
        trigger_msg = #msg_ref{id = 1004, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = []
    },
    Msg1 = #message{id = 1001, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m1},
    Msg2 = #message{id = 1002, sender = {connector, some}, receiver = {inst, IID1}, resp_to = 1001,      date = erlang:now(), body = m2},
    Msg3 = #message{id = 1003, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m3},
    Msg4 = #message{id = 1004, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = erlang:now(), body = m4},
    %%
    %%  Add ordinary transition
    {ok, IID1, 1} = eproc_store:add_transition(Store, Trn1, [Msg1, Msg2, Msg3]),
    {ok, #instance{status = running, state = #inst_state{
        inst_id = IID1, trn_nr = 1,
        sname = [s1], sdata = d1,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add ordinary transition
    {ok, IID1, 2} = eproc_store:add_transition(Store, Trn2, [Msg4]),
    {ok, #instance{status = running, state = #inst_state{
        inst_id = IID1, trn_nr = 2,
        sname = [s2], sdata = d2,
        attr_last_id = 1, attrs_active = [_],
        interrupt = undefined
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    ok.


