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
    eproc_store_core_test_resolve_msg_dst/1,
    eproc_store_core_test_load_running/1,
    eproc_store_core_test_get_state/1,
    eproc_store_core_test_attrs/1,
    eproc_store_router_test_attrs/1,
    eproc_store_meta_test_attrs/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include("eproc.hrl").


%%
%%
%%
testcases(core) -> [
    eproc_store_core_test_unnamed_instance,
    eproc_store_core_test_named_instance,
    eproc_store_core_test_suspend_resume,
    eproc_store_core_test_add_transition,
    eproc_store_core_test_resolve_msg_dst,
    eproc_store_core_test_load_running,
    eproc_store_core_test_get_state,
    eproc_store_core_test_attrs
    ];

testcases(router) -> [
    eproc_store_router_test_attrs
    ];

testcases(meta) -> [
    eproc_store_meta_test_attrs
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
    Now = os:timestamp(),
    #instance{
        inst_id = undefined,
        group = new,
        name = undefined,
        module = some_fsm,
        args = [arg1],
        opts = [{o, p}],
        start_spec = undefined,
        status = running,
        created = Now,
        create_node = undefined,
        terminated = undefined,
        archived = undefined,
        interrupt = undefined,
        curr_state = #inst_state{
            stt_id = 0,
            sname = [],
            sdata = {state, a, b},
            timestamp = Now,
            attr_last_nr = 0,
            attrs_active = [],
            interrupts = []
        },
        arch_state = undefined,
        transitions = undefined
    }.


%%
%%
%%
trn_value(InstId, TrnNr, async_void) ->
    Timestamp = {0, TrnNr, 0},
    MsgCid = {InstId, TrnNr, 0, recv},
    Trn = #transition{
        trn_id = TrnNr,
        sname = [s, TrnNr],
        sdata = {d, TrnNr},
        timestamp = Timestamp,
        duration = 13,
        trn_node = undefined,
        trigger_type = event,
        trigger_msg = #msg_ref{cid = MsgCid, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 0,
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg = #message{
        msg_id = MsgCid,
        sender = {connector, some},
        receiver = {inst, InstId},
        resp_to = undefined,
        date = Timestamp,
        body = {m, TrnNr}
    },
    {ok, Trn, [Msg]}.



%% =============================================================================
%%  Testcases: Core
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
    Inst = #instance{curr_state = State} = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{group = new}),
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{group = 897}),
    true = undefined =/= IID1,
    true = undefined =/= IID2,
    true = IID1 =/= IID2,
    true = is_tuple(IID1),
    2    = tuple_size(IID1),
    %%  Try to get instance headers.
    {ok, Inst1 = #instance{inst_id = IID1, group = GRP1}} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2 = #instance{inst_id = IID2, group = GRP2}} = eproc_store:get_instance(Store, {inst, IID2}, header),
    {ok, NodeRef} = eproc_store:get_node(Store),
    #instance{created = {_,_,_}} = Inst1,
    Inst1 = Inst#instance{inst_id = IID1, group = GRP1, create_node = NodeRef, curr_state = undefined},
    Inst2 = Inst#instance{inst_id = IID2, group = GRP2, create_node = NodeRef, curr_state = undefined},
    false = is_atom(GRP1),
    897 = GRP2,
    #instance{create_node = CreateNode} = Inst1,
    false = CreateNode =:= undefined,
    %%  Try to get instance state
    {ok, #instance{curr_state = undefined    }} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, #instance{curr_state = #inst_state{}}} = eproc_store:get_instance(Store, {inst, IID1}, recent),
    {ok, [
        #instance{inst_id = IID1, curr_state = #inst_state{}},
        #instance{inst_id = IID2, curr_state = #inst_state{}}
    ]} = eproc_store:get_instance(Store, {list, [{inst, IID1}, {inst, IID2}]}, recent),
    {error, _} = eproc_store:get_instance(Store, {list, [{inst, IID1}, {inst, IID2}, {inst, some}]}, recent),
    {ok, #instance{curr_state = State1}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    #inst_state{stt_id = 0, sname = [], sdata = {state, a, b}, timestamp = {_, _, _}} = State1,
    %%  Try to load instance data.
    {ok, LoadedInst = #instance{inst_id = IID1, group = GRP1}} = eproc_store:load_instance(Store, {inst, IID1}),
    LoadedInst = Inst#instance{inst_id = IID1, group = GRP1, create_node = NodeRef, curr_state = State#inst_state{}},
    %%  Kill created instances.
    {ok, IID1} = eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}),
    {ok, IID1} = eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}),
    {ok, IID2} = eproc_store:set_instance_killed(Store, {inst, IID2}, #user_action{}),
    {error, not_found} = eproc_store:set_instance_killed(Store, {inst, some}, #user_action{}),
    {ok, #instance{
        inst_id = IID1,
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
    Inst = #instance{curr_state = State} = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{group = new, name = test_named_instance_a}),
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{group = 897, name = test_named_instance_b}),
    {error, {already_created, IID2}} = eproc_store:add_instance(Store, Inst#instance{group = 897, name = test_named_instance_b}),
    true = undefined =/= IID1,
    true = undefined =/= IID2,
    true = IID1 =/= IID2,
    %%  Try to get instance headers by IID and by name.
    {ok, Inst1 = #instance{inst_id = IID1, group = GRP1, curr_state = undefined}} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2 = #instance{inst_id = IID2, group = GRP2, curr_state = undefined}} = eproc_store:get_instance(Store, {inst, IID2}, header),
    {error, not_found}  = eproc_store:get_instance(Store, {inst, some}, header),
    {ok, Inst1}         = eproc_store:get_instance(Store, {name, test_named_instance_a}, header),
    {ok, Inst2}         = eproc_store:get_instance(Store, {name, test_named_instance_b}, header),
    {error, not_found}  = eproc_store:get_instance(Store, {name, test_named_instance_c}, header),
    {ok, NodeRef}       = eproc_store:get_node(Store),
    Inst1 = Inst#instance{inst_id = IID1, group = GRP1, name = test_named_instance_a, create_node = NodeRef, curr_state = undefined},
    Inst2 = Inst#instance{inst_id = IID2, group = GRP2, name = test_named_instance_b, create_node = NodeRef, curr_state = undefined},
    false = is_atom(GRP1),
    897 = GRP2,
    %%  Try to load instance data.
    {ok, LoadedInst = #instance{inst_id = IID1, group = GRP1}} = eproc_store:load_instance(Store, {name, test_named_instance_a}),
    LoadedInst = Inst#instance{inst_id = IID1, group = GRP1, name = test_named_instance_a, create_node = NodeRef, curr_state = State#inst_state{}},
    %%  Kill created instances.
    {ok, IID1}         = eproc_store:set_instance_killed(Store, {name, test_named_instance_a}, #user_action{}),
    {error, not_found} = eproc_store:set_instance_killed(Store, {name, test_named_instance_a}, #user_action{}),
    {ok, IID2}         = eproc_store:set_instance_killed(Store, {name, test_named_instance_b}, #user_action{}),
    {error, not_found} = eproc_store:set_instance_killed(Store, {name, test_named_instance_v}, #user_action{}),
    {ok, #instance{
        inst_id = IID1,
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
    #instance{status = suspended, interrupt = #interrupt{}} = Inst1Suspended,
    #instance{status = suspended, interrupt = #interrupt{}} = Inst2Suspended,
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
    #instance{status = resuming, interrupt = #interrupt{}} = Inst1Resuming,
    #instance{status = resuming, interrupt = #interrupt{}} = Inst2Resuming,
    %%  Mark them resumed
    ok = eproc_store:set_instance_resumed(Store, IID1, 0),
    ok = eproc_store:set_instance_resumed(Store, IID1, 0),
    {error, running}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),   %% Try resume running FSM
    {ok, Inst1Resumed} = eproc_store:get_instance(Store, {inst, IID1}, current),
    #instance{status = running, interrupt = undefined} = Inst1Resumed,
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
        trn_id = 1,
        sname = [s1],
        sdata = d1,
        timestamp = os:timestamp(),
        duration = 13,
        trn_node = undefined,
        trigger_type = event,
        trigger_msg = #msg_ref{cid = 1011, peer = {connector, some}},
        trigger_resp = #msg_ref{cid = 1012, peer = {connector, some}},
        trn_messages = [#msg_ref{cid = 1013, peer = {connector, some}}],
        attr_last_nr = 1,
        attr_actions = [#attr_action{module = m, attr_nr = 1, action = {create, undefined, [], some}}],
        inst_status = running,
        interrupts = undefined
    },
    Msg11 = #message{msg_id = 1011, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m11},
    Msg12 = #message{msg_id = 1012, sender = {connector, some}, receiver = {inst, IID1}, resp_to = 1011,      date = os:timestamp(), body = m12},
    Msg13 = #message{msg_id = 1013, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m13},
    {ok, IID1, 1} = eproc_store:add_transition(Store, IID1, Trn1, [Msg11, Msg12, Msg13]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 1, sname = [s1], sdata = d1, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add another ordinary transition
    Trn2 = Trn1#transition{
        trn_id = 2,
        sname = [s2],
        sdata = d2,
        trigger_msg = #msg_ref{cid = 1021, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = []
    },
    Msg21 = #message{msg_id = 1021, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m21},
    {ok, IID1, 2} = eproc_store:add_transition(Store, IID1, Trn2, [Msg21]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 2, sname = [s2], sdata = d2, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Suspend by transition.
    Trn3 = Trn1#transition{
        trn_id = 3,
        sname = [s3],
        sdata = d3,
        trigger_msg = #msg_ref{cid = 1031, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = suspended,
        interrupts = [#interrupt{reason = {fault, some_reason}}]
    },
    Msg31 = #message{msg_id = 1031, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m31},
    {ok, IID1, 3} = eproc_store:add_transition(Store, IID1, Trn3, [Msg31]),
    {ok, #instance{status = suspended,
        curr_state = #inst_state{
            stt_id = 3, sname = [s3], sdata = d3, timestamp = {_, _, _},
            attr_last_nr = 1, attrs_active = [_]
        },
        interrupt = #interrupt{
            intr_id = undefined,
            status = active,
            suspended = {_, _, _},
            reason = {fault, some_reason},
            resumes = []
        }
    }} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Resume with transition.
    {ok, IID1, _}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    {ok, IID1, _}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    {ok, IID1, _}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    Trn4 = Trn1#transition{
        trn_id = 4,
        sname = [s4],
        sdata = d4,
        trigger_msg = #msg_ref{cid = 1041, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg41 = #message{msg_id = 1041, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m41},
    {ok, IID1, 4} = eproc_store:add_transition(Store, IID1, Trn4, [Msg41]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 4, sname = [s4], sdata = d4, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Terminate FSM.
    Trn5 = Trn1#transition{
        trn_id = 5,
        sname = [s5],
        sdata = d5,
        trigger_msg = #msg_ref{cid = 1051, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = completed,
        interrupts = undefined
    },
    Msg51 = #message{msg_id = 1051, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m51},
    {ok, IID1, 5} = eproc_store:add_transition(Store, IID1, Trn5, [Msg51]),
    {ok, #instance{status = completed, interrupt = undefined, curr_state = #inst_state{
        stt_id = 5, sname = [s5], sdata = d5, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add transition to the terminated FSM.
    Trn6 = Trn1#transition{
        trn_id = 6,
        sname = [s6],
        sdata = d6,
        trigger_msg = #msg_ref{cid = 1061, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg61 = #message{msg_id = 1061, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m61},
    {error, terminated} = eproc_store:add_transition(Store, IID1, Trn6, [Msg61]),
    {ok, #instance{status = completed, interrupt = undefined, curr_state = #inst_state{
        stt_id = 5, sname = [s5], sdata = d5, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    ok.


%%
%%  Check if message destination is resolved in the cases, when it was
%%  left partially resolved at runtime. This test checks the following
%%  store functions:
%%
%%    * `get_transition/4`,
%%    * `get_message/3`.
%%
eproc_store_core_test_resolve_msg_dst(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst),
    {ok, IID2} = eproc_store:add_instance(Store, Inst),
    {ok, NodeRef} = eproc_store:get_node(Store),
    %%  Add transitions.
    Msg1r = #message{msg_id = {IID1, 1, 0, recv}, sender = {ext, some},  receiver = {inst, IID1},      resp_to = undefined, date = os:timestamp(), body = m1},
    Msg2s = #message{msg_id = {IID1, 1, 2, sent}, sender = {inst, IID1}, receiver = {inst, undefined}, resp_to = undefined, date = os:timestamp(), body = m2},
    Msg2r = #message{msg_id = {IID1, 1, 2, recv}, sender = {inst, IID1}, receiver = {inst, IID2},      resp_to = undefined, date = os:timestamp(), body = m2},
    Msg3r = #message{msg_id = {IID1, 1, 3, recv}, sender = {inst, IID1}, receiver = {inst, IID2},      resp_to = undefined, date = os:timestamp(), body = m3},
    Trn1 = #transition{
        trn_id = 1,
        sname = [s1],
        sdata = d1,
        timestamp = os:timestamp(),
        duration = 13,
        trn_node = undefined,
        trigger_type = event,
        trigger_msg = #msg_ref{cid = {IID1, 1, 0, recv}, peer = {ext, some}},
        trigger_resp = undefined,
        trn_messages = [#msg_ref{cid = {IID1, 1, 2, sent}, peer = {inst, undefined}}],
        attr_last_nr = 1,
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Trn2 = Trn1#transition{
        trn_id = 1,
        trigger_msg = #msg_ref{cid = {IID1, 1, 2, recv}, peer = {inst, IID1}},
        trn_messages = []
    },
    Trn3 = Trn1#transition{
        trn_id = 2,
        trigger_msg = #msg_ref{cid = {IID1, 1, 3, recv}, peer = {inst, IID1}},
        trn_messages = []
    },
    Trn1Fix = Trn1#transition{
        trn_node = NodeRef,
        trn_messages = [#msg_ref{cid = {IID1, 1, 2, sent}, peer = {inst, IID2}}],
        interrupts = []
    },
    Trn2Fix = Trn2#transition{
        trn_node = NodeRef,
        interrupts = []
    },
    {ok, IID1, 1} = eproc_store:add_transition(Store, IID1, Trn1, [Msg1r, Msg2s]),
    {ok, IID2, 1} = eproc_store:add_transition(Store, IID2, Trn2, [Msg2r]),
    {ok, IID2, 2} = eproc_store:add_transition(Store, IID2, Trn3, [Msg3r]),
    %%  Get the stored data.
    Msg1 = Msg1r#message{msg_id = {IID1, 1, 0}},
    Msg2 = Msg2r#message{msg_id = {IID1, 1, 2}}, %% Receiver = {inst, IID2}
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 0      }, all), is({ok, Msg1})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 0, sent}, all), is({ok, Msg1})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 0, recv}, all), is({ok, Msg1})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 2      }, all), is({ok, Msg2})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 2, sent}, all), is({ok, Msg2})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 2, recv}, all), is({ok, Msg2})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 1      }, all), is({error, not_found})),
    ?assertThat(eproc_store:get_transition(Store, {inst, IID1}, 1, all), is({ok, Trn1Fix})),
    ?assertThat(eproc_store:get_transition(Store, {inst, IID2}, 1, all), is({ok, Trn2Fix})),
    ?assertThat(eproc_store:get_transition(Store, {inst, IID2}, 3, all), is({error, not_found})),
    {ok, Trns1a} = eproc_store:get_transition(Store, {inst, IID1}, {list, 1,       100}, all),
    {ok, Trns1b} = eproc_store:get_transition(Store, {inst, IID1}, {list, 1,       0  }, all),
    {ok, Trns2a} = eproc_store:get_transition(Store, {inst, IID2}, {list, current, 100}, all),
    {ok, Trns2b} = eproc_store:get_transition(Store, {inst, IID2}, {list, current, 1  }, all),
    ?assertThat(Trns1a, has_length(1)),
    ?assertThat(Trns1b, has_length(0)),
    ?assertThat(Trns2a, has_length(2)),
    ?assertThat(Trns2b, has_length(1)),
    ok.


%%
%%  Check, if load_running works.
%%
eproc_store_core_test_load_running(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [1]}}),   % Will be resuming
    {ok, IID2} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [2]}}),   % Will be suspended
    {ok, IID3} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [3]}}),   % Will be killed
    {ok, IID4} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [4]}}),   % Will be running
    {ok, IID5} = eproc_store:add_instance(Store, Inst#instance{start_spec = {default, [5]}}),   % Will be running also
    %%  Change instance statuses.
    {ok, IID1} = eproc_store:set_instance_suspended(Store, {inst, IID1}, #user_action{}),
    {ok, IID2} = eproc_store:set_instance_suspended(Store, {inst, IID2}, #user_action{}),
    {ok, IID1, {default, [1]}}  = eproc_store:set_instance_resuming(Store, {inst, IID1}, unchanged, #user_action{}),
    {ok, IID3} = eproc_store:set_instance_killed(Store, {inst, IID3}, #user_action{}),
    %%  Get instances to start / run.
    {ok, Running} = eproc_store:load_running(Store, fun (_, _) -> true end),
    [  ] = [ ok || {{inst, I}, {default, [1]}} <- Running, I =:= IID1 ],
    [  ] = [ ok || {{inst, I}, {default, [2]}} <- Running, I =:= IID2 ],
    [  ] = [ ok || {{inst, I}, {default, [3]}} <- Running, I =:= IID3 ],
    [ok] = [ ok || {{inst, I}, {default, [4]}} <- Running, I =:= IID4 ],
    [ok] = [ ok || {{inst, I}, {default, [5]}} <- Running, I =:= IID5 ],
    ok.


%%
%%
%%
eproc_store_core_test_get_state(Config) ->
    Store = store(Config),
    %%  Prepare the data.
    Inst = inst_value(),
    {ok, IID} = eproc_store:add_instance(Store, Inst),
    {ok, Trn1, Msgs1} = trn_value(IID, 1, async_void),
    {ok, Trn2, Msgs2} = trn_value(IID, 2, async_void),
    {ok, Trn3, Msgs3} = trn_value(IID, 3, async_void),
    {ok, Trn4, Msgs4} = trn_value(IID, 4, async_void),
    {ok, Trn5, Msgs5} = trn_value(IID, 5, async_void),
    A1C = #attr_action{module = m, attr_nr = 1, action = {create, undefined, [], some1}},
    A2C = #attr_action{module = m, attr_nr = 2, action = {create, undefined, [], some2}},
    A3C = #attr_action{module = m, attr_nr = 3, action = {create, undefined, [], some3}},
    A2D = #attr_action{module = m, attr_nr = 2, action = {remove, {scope, [ohoho]}}},
    A1U1 = #attr_action{module = m, attr_nr = 1, action = {update, [wider], some1_b}},
    A1U2 = #attr_action{module = m, attr_nr = 1, action = {update, [wider], some1_c}},
    A3U1 = #attr_action{module = m, attr_nr = 3, action = {update, [other], some3_b}},
    {ok, IID, 1} = eproc_store:add_transition(Store, IID, Trn1#transition{attr_last_nr = 0, attr_actions = []},           Msgs1),
    {ok, IID, 2} = eproc_store:add_transition(Store, IID, Trn2#transition{attr_last_nr = 2, attr_actions = [A1C, A2C]},   Msgs2),
    {ok, IID, 3} = eproc_store:add_transition(Store, IID, Trn3#transition{attr_last_nr = 3, attr_actions = [A2D, A3C]},   Msgs3),
    {ok, IID, 4} = eproc_store:add_transition(Store, IID, Trn4#transition{attr_last_nr = 3, attr_actions = [A1U1]},       Msgs4),
    {ok, IID, 5} = eproc_store:add_transition(Store, IID, Trn5#transition{attr_last_nr = 3, attr_actions = [A1U2, A3U1]}, Msgs5),
    %   Get the current state.
    {ok, State5 = #inst_state{
        stt_id = 5,
        sname = [s, 5],
        sdata = {d, 5},
        timestamp = {0, 5, 0},
        attr_last_nr = 3,
        attrs_active = Attrs5 = [_, _],
        interrupts = []
    }} = eproc_store:get_state(Store, {inst, IID}, current, all),
    #attribute{
        module = m, name = undefined, scope = [wider], data = some1_c,
        from = 2, upds = [_, _], till = undefined, reason = undefined
    } = lists:keyfind(1, #attribute.attr_id, Attrs5),
    #attribute{
        module = m, name = undefined, scope = [other], data = some3_b,
        from = 3, upds = [5], till = undefined, reason = undefined
    } = lists:keyfind(3, #attribute.attr_id, Attrs5),
    %   Get the current state by its number.
    {ok, State5} = eproc_store:get_state(Store, {inst, IID}, 5, all),
    %   Get some older state.
    {ok, #inst_state{
        stt_id = 2,
        sname = [s, 2],
        sdata = {d, 2},
        timestamp = {0, 2, 0},
        attr_last_nr = 2,
        attrs_active = Attrs2 = [_, _],
        interrupts = []
    }} = eproc_store:get_state(Store, {inst, IID}, 2, all),
    #attribute{
        module = m, name = undefined, scope = [], data = some1,
        from = 2, upds = [], till = undefined, reason = undefined
    } = lists:keyfind(1, #attribute.attr_id, Attrs2),
    #attribute{
        module = m, name = undefined, scope = [], data = some2,
        from = 2, upds = [], till = undefined, reason = undefined
    } = lists:keyfind(2, #attribute.attr_id, Attrs2),
    %   Get a list of states
    {ok, [
        #inst_state{stt_id = 4, sname = [s, 4], sdata = {d, 4}, attrs_active = Attrs4 = [_, _], interrupts = []},
        #inst_state{stt_id = 3, sname = [s, 3], sdata = {d, 3}, attrs_active = Attrs3 = [_, _], interrupts = []},
        #inst_state{stt_id = 2, sname = [s, 2], sdata = {d, 2}, attrs_active = Attrs2 = [_, _], interrupts = []}
    ]} = eproc_store:get_state(Store, {inst, IID}, {list, 4, 3}, all),
    #attribute{data = some1,   from = 2, upds = []}  = lists:keyfind(1, #attribute.attr_id, Attrs3),
    #attribute{data = some3,   from = 3, upds = []}  = lists:keyfind(3, #attribute.attr_id, Attrs3),
    #attribute{data = some1_b, from = 2, upds = [4]} = lists:keyfind(1, #attribute.attr_id, Attrs4),
    #attribute{data = some3,   from = 3, upds = []}  = lists:keyfind(3, #attribute.attr_id, Attrs4),
    ok.


%%
%%  Check if generic attribute functionality works.
%%
%%    * Unknown attribute is handled, if it does not requires a store.
%%    * Transition is rejected, if unkown attribute is added that requires a store.
%%
eproc_store_core_test_attrs(Config) ->
    Store = store(Config),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst),
    %%
    %%  Add attribute that needs no store.
    %%
    Trn1 = #transition{
        trn_id = 1, sname = [s1], sdata = d1,
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = 1011, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = m, attr_nr = 1, needs_store = false, action = {create, n11, [], some}}
        ],
        inst_status = running,interrupts = undefined
    },
    Msg11 = #message{msg_id = 1011, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m11},
    {ok, IID1, 1} = eproc_store:add_transition(Store, IID1, Trn1, [Msg11]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 1, sname = [s1], sdata = d1, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [Attr11]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    #attribute{
        attr_id = 1,
        module = m,
        name = n11,
        scope = [],
        data = some,
        from = 1,
        upds = [],
        till = undefined,
        reason = undefined
    } = Attr11,
    %%
    %%  Add another ordinary transition
    %%
    Trn2 = Trn1#transition{
        trn_id = 2,
        sname = [s2],
        sdata = d2,
        trigger_msg = #msg_ref{cid = 1021, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [
            #attr_action{module = m2, attr_nr = 2, needs_store = true, action = {create, n11, [], some}}
        ]
    },
    Msg21 = #message{msg_id = 1021, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m21},
    ok = try eproc_store:add_transition(Store, IID1, Trn2, [Msg21]) of
        {ok, IID1, _} -> error
    catch
        _:_ -> ok
    end,
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 1,
        sname = [s1], sdata = d1, timestamp = {_, _, _},
        attr_last_nr = 1,
        attrs_active = [Attr11]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    ok.



%% =============================================================================
%%  Testcases: Router
%% =============================================================================

%%
%%  Check if store operations for handling `eproc_router` attributes (keys) works.
%%
eproc_store_router_test_attrs(Config) ->
    Store = store(Config),
    Key1 = {eproc_store_router_test_attrs, now()},
    Key2 = {eproc_store_router_test_attrs, now()},
    RouterOpts = [{store, Store}],
    %%
    %%  Add instances.
    %%
    {ok, IID} = eproc_store:add_instance(Store, inst_value()),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, []})),
    %%
    %%  Add a key synchronously.
    %%
    {ok, SyncRef} = eproc_store:attr_task(Store, eproc_router, {key_sync, Key2, IID, false}),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID]})),
    %%
    %%  Add the key attributes.
    %%
    Trn1 = #transition{
        trn_id = 1, sname = [s1], sdata = d1,
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = 1011, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {create, undefined, [s1], {data, Key1, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 2, needs_store = true, action = {create, undefined, [],   {data, Key2, SyncRef}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg11 = #message{msg_id = 1011, sender = {connector, some}, receiver = {inst, IID}, resp_to = undefined, date = os:timestamp(), body = m11},
    {ok, IID, 1} = eproc_store:add_transition(Store, IID, Trn1, [Msg11]),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, [IID]})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID]})),
    %%
    %%  Remove one attr by scope.
    %%
    Trn2 = Trn1#transition{
        trn_id = 2, sname = [s2], sdata = d2,
        trigger_msg = #msg_ref{cid = 1021, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 2,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {remove, {scope, [s2]}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg21 = #message{msg_id = 1021, sender = {connector, some}, receiver = {inst, IID}, resp_to = undefined, date = os:timestamp(), body = m11},
    {ok, IID, 2} = eproc_store:add_transition(Store, IID, Trn2, [Msg21]),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID]})),
    %%
    %% Check, if taks are available after instance is terminated.
    ?assertThat(eproc_store:set_instance_killed(Store, {inst, IID}, #user_action{}), is({ok, IID})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, []})),
    ok.



%% =============================================================================
%%  Testcases: Meta
%% =============================================================================

%%
%%  Check if store operations for handling `eproc_module` attributes (tags) works.
%%
eproc_store_meta_test_attrs(Config) ->
    Store = store(Config),
    Tag1 = erlang:term_to_binary(erlang:now()),
    Tag2 = erlang:term_to_binary(erlang:now()),
    Tag3 = erlang:term_to_binary(erlang:now()),
    Type1 = <<"eproc_store_meta_test_attrs_x">>,
    Type2 = <<"eproc_store_meta_test_attrs_y">>,
    Opts = [{store, Store}],
    %%
    %%  Add instances.
    %%
    {ok, IID1} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID2} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID3} = eproc_store:add_instance(Store, inst_value()),
    ?assertThat(eproc_meta:get_instances({tags, [{Tag1, undefined}]}, Opts), is({ok, []})),
    ?assertThat(eproc_meta:get_instances({tags, [{Tag2, undefined}]}, Opts), is({ok, []})),
    %%
    %%  Add the key attributes.
    %%
    AddTrnFun = fun (IID, AttrActions) ->
        Trn = #transition{
            trn_id = 1, sname = [s1], sdata = d1, timestamp = os:timestamp(), trn_node = undefined, duration = 13, trigger_type = event,
            trigger_msg = #msg_ref{cid = {IID, 1, 0, recv}, peer = {connector, some}}, trigger_resp = undefined, trn_messages = [],
            attr_last_nr = 1, attr_actions = AttrActions, inst_status = running, interrupts = undefined
        },
        Msg = #message{msg_id = {IID, 1, 0, recv}, sender = {connector, some}, receiver = {inst, IID}, resp_to = undefined, date = os:timestamp(), body = m11},
        {ok, IID, 1} = eproc_store:add_transition(Store, IID, Trn, [Msg])
    end,
    AddTrnFun(IID1, [
        #attr_action{module = eproc_meta, attr_nr = 1, needs_store = true, action = {create, undefined, [], {data, Tag1, Type1}}},
        #attr_action{module = eproc_meta, attr_nr = 2, needs_store = true, action = {create, undefined, [], {data, Tag3, Type1}}}
    ]),
    AddTrnFun(IID2, [
        #attr_action{module = eproc_meta, attr_nr = 1, needs_store = true, action = {create, undefined, [], {data, Tag1, Type2}}}
    ]),
    AddTrnFun(IID3, [
        #attr_action{module = eproc_meta, attr_nr = 1, needs_store = true, action = {create, undefined, [], {data, Tag2, Type2}}}
    ]),
    {ok, Res1} = eproc_meta:get_instances({tags, [{Tag1, undefined}]}, Opts),
    {ok, Res2} = eproc_meta:get_instances({tags, [{Tag2, undefined}]}, Opts),
    {ok, Res3} = eproc_meta:get_instances({tags, [{Tag1, Type1}]}, Opts),
    {ok, Res4} = eproc_meta:get_instances({tags, [{Tag2, Type1}]}, Opts),
    {ok, Res5} = eproc_meta:get_instances({tags, [{Tag1, undefined}, {Tag3, undefined}]}, Opts),
    ?assertThat(Res1, contains_member(IID1)),
    ?assertThat(Res1, contains_member(IID2)),
    ?assertThat(Res1, has_length(2)),
    ?assertThat(Res2, is([IID3])),
    ?assertThat(Res3, is([IID1])),
    ?assertThat(Res4, is([])),
    ?assertThat(Res5, is([IID1])),
    %%
    %% Check, if taks are available after instance is terminated.
    ?assertThat(eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}),           is({ok, IID1})),
    ?assertThat(eproc_meta:get_instances({tags, [{Tag1, undefined}, {Tag3, undefined}]}, Opts), is({ok, [IID1]})),
    ok.


