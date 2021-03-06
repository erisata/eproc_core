%/--------------------------------------------------------------------
%| Copyright 2013-2016 Erisata, UAB (Ltd.)
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
    eproc_store_core_test_get_instance_filter/1,
    eproc_store_core_test_suspend_resume/1,
    eproc_store_core_test_add_transition/1,
    eproc_store_core_test_resolve_msg_dst/1,
    eproc_store_core_test_load_running/1,
    eproc_store_core_test_get_state/1,
    eproc_store_core_test_attrs/1,
    eproc_store_router_test_attrs/1,
    eproc_store_router_test_multiple/1,
    eproc_store_router_test_uniq/1,
    eproc_store_meta_test_attrs/1,
    eproc_store_attachment_test_instid/1,
    eproc_store_attachment_test_name/1
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
    eproc_store_core_test_get_instance_filter,
    eproc_store_core_test_suspend_resume,
    eproc_store_core_test_add_transition,
    eproc_store_core_test_resolve_msg_dst,
    eproc_store_core_test_load_running,
    eproc_store_core_test_get_state,
    eproc_store_core_test_attrs
    ];

testcases(router) -> [
    eproc_store_router_test_attrs,
    eproc_store_router_test_multiple,
    eproc_store_router_test_uniq
    ];

testcases(meta) -> [
    eproc_store_meta_test_attrs
    ];

testcases(attachment) -> [
    eproc_store_attachment_test_instid,
    eproc_store_attachment_test_name
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
        app = test,
        type = some_fsm,
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
%% Check if get_instance works with filters
%%
eproc_store_core_test_get_instance_filter(Config) ->
    Store = store(Config),
%     DFun = fun(DateTime) ->
%         Seconds = calendar:datetime_to_gregorian_seconds(DateTime) - 62167219200,
%         {Seconds div 1000000, Seconds rem 1000000, 0}.
%     end,
    AddTrnFun = fun (IID, TrnId, Timestamp, AttrActions) ->
        Trn = #transition{
            trn_id = TrnId, sname = [new_state], sdata = some_data, timestamp = Timestamp, trn_node = undefined, duration = 16, trigger_type = event,
            trigger_msg = #msg_ref{cid = {IID, TrnId, 0, recv}, peer = {connector, some}}, trigger_resp = undefined, trn_messages = [],
            attr_last_nr = 1, attr_actions = AttrActions, inst_status = running, interrupts = undefined
        },
        Msg = #message{msg_id = {IID, TrnId, 0, recv}, sender = {connector, some}, receiver = {inst, IID}, resp_to = undefined, date = Timestamp, body = some_message},
        {ok, IID, TrnId} = eproc_store:add_transition(Store, IID, Trn, [Msg])
    end,
    Now = os:timestamp(),
    OldDate1 = eproc_timer:timestamp_before({3,day}, Now),
    OldDate2 = eproc_timer:timestamp_before({2,day}, Now),
    OldDate3 = eproc_timer:timestamp_before({1,day}, Now),
    OldDate4 = eproc_timer:timestamp_before({12,hour}, Now),
    TagName1 = <<"123">>, TagType1 = <<"cust_nr">>,
    TagName2 = <<"rejected">>, TagType2 = <<"resolution">>,
    Group1 = {1, main}, % TODO: group id doesn't match instance id.
    Group2 = {5, main},
    % Create and add testing instances
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store,
        Inst#instance{name = testing_name, created = OldDate1, group = Group1}),
    {ok, IID2} = eproc_store:add_instance(Store,
        Inst#instance{created = OldDate3, group = Group1}),
    {ok, IID3} = eproc_store:add_instance(Store,
        Inst#instance{module = another_fsm, created = OldDate1, terminated = OldDate3, status = killed}),
    {ok, IID4} = eproc_store:add_instance(Store,
        Inst#instance{module = some_other_fsm}),
    {ok, IID5} = eproc_store:add_instance(Store,
        Inst#instance{created = os:timestamp(), name = other_name, status = resuming, group = Group2}),
    InstRefs = [ {inst, IID} || IID <- [IID1, IID2, IID3, IID4, IID5] ],
    % Add transitions for testing
    AddTrnFun(IID1, 1, OldDate1, []),
    AddTrnFun(IID1, 2, os:timestamp(), []),
    AddTrnFun(IID2, 1, OldDate3, [
        #attr_action{module = eproc_meta, attr_nr = 1, needs_store = true, action = {create, {tag,TagName1,TagType1}, [], {data, TagName1, TagType1}}}
    ]),
    AddTrnFun(IID4, 1, OldDate1, [
        #attr_action{module = eproc_meta, attr_nr = 1, needs_store = true, action = {create, {tag,TagName1,TagType1}, [], {data, TagName1, TagType1}}},
        #attr_action{module = eproc_meta, attr_nr = 2, needs_store = true, action = {create, {tag,TagName2,TagType2}, [], {data, TagName2, TagType2}}}
    ]),
    AddTrnFun(IID5, 1, os:timestamp(), [
        #attr_action{module = eproc_meta, attr_nr = 1, needs_store = true, action = {create, {tag,TagName2,TagType2}, [], {data, TagName2, TagType2}}}
    ]),
    % Get reference instances
    {ok, _} = eproc_store:get_instance(Store, {list, InstRefs}, current), %% To synchronize state on weak consistency stores.
    {ok, Inst1} = eproc_store:get_instance(Store, {inst, IID1}, header),
    {ok, Inst2} = eproc_store:get_instance(Store, {inst, IID2}, header),
    {ok, Inst3} = eproc_store:get_instance(Store, {inst, IID3}, header),
    {ok, Inst4} = eproc_store:get_instance(Store, {inst, IID4}, header),
    {ok, Inst5} = eproc_store:get_instance(Store, {inst, IID5}, header),
    % Performing sucessful simple tests
    From = 1,
    Count = 99,
    {ok, {_, _, Res00}} = eproc_store:get_instance(Store, {filter, {From+2, 3}, []}, header),
    {ok, {_, _, Res01}} = eproc_store:get_instance(Store, {filter, {From, Count}, []}, header),
    {ok, {_, _, Res02}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, IID1}]}, header),
    {ok, {_, _, Res03}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{name, testing_name}]}, header),
    {ok, {_, _, Res04}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn, undefined, OldDate2}]}, header),
    {ok, {_, _, Res05}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn, OldDate2, undefined}]}, header),
    {ok, {_, _, Res06}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn, OldDate2, OldDate4}]}, header),
    {ok, {_, _, Res07}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{created, undefined, OldDate2}]}, header),
    {ok, {_, _, Res08}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{created, OldDate2, undefined}]}, header),
    {ok, {_, _, Res09}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{created, OldDate2, OldDate4}]}, header),
    {ok, {_, _, Res10}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, [{<<"123">>, <<"cust_nr">>}]}]}, header),
    {ok, {_, _, Res11}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, [{<<"123">>, <<"cust_nr">>},{<<"rejected">>, <<"resolution">>}]}]}, header),
    {ok, {_, _, Res12}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, [{<<"123">>, <<"cust_nr">>}]}, {tag,[{<<"rejected">>, <<"resolution">>}]}]}, header),
    {ok, {_, _, Res13}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{module, some_other_fsm}]}, header),
    {ok, {_, _, Res14}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{status, resuming}]}, header),
    {ok, {_, _, Res15}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, {12,hour}}]}, header),
    {ok, {_, _, Res16}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, [{2,day},{1,hour}]}]}, header),
    {ok, {_, _, Res16}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, {12,hour}}, {age, [{2,day},{1,hour}]}]}, header),
    {ok, {_, _, Res17}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, [IID1, IID2]}]}, header),
    {ok, {_, _, Res18}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, [IID1, IID2, wrong_id]}]}, header),
    {ok, {_, _, Res19}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{name, [testing_name, other_name]}]}, header),
    {ok, {_, _, Res20}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{name, [wrong_name, testing_name, other_name]}]}, header),
    {ok, {_, _, Res21}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, [<<"123">>]}]}, header),
    {ok, {_, _, Res22}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, [{<<"123">>, undefined}]}]}, header),
    {ok, {_, _, Res23}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, [{<<"123">>, undefined},{<<"wrong">>,<<"tag">>}]}]}, header),
    {ok, {_, _, Res24}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, {<<"123">>, <<"cust_nr">>}}]}, header),
    {ok, {_, _, Res25}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, {<<"123">>, undefined}}]}, header),
    {ok, {_, _, Res26}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, <<"123">>}]}, header),
    {ok, {_, _, Res27}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{module, [some_other_fsm, another_fsm]}]}, header),
    {ok, {_, _, Res28}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{module, [some_other_fsm, wrong_fsm, another_fsm]}]}, header),
    {ok, {_, _, Res29}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{status, [resuming, killed]}]}, header),
    {ok, {_, _, Res30}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{status, [suspended, resuming, killed]}]}, header),
    {ok, {_, _, Res31}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn_age, {12,hour}}]}, header),
    {ok, {_, _, Res31}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn_age, {12,hour}}, {last_trn_age, [{2,day},{1,hour}]}]}, header),
    {ok, {_, _, Res32}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn_age, [{2,day},{1,hour}]}]}, header),
    {ok, {_, _, Res33}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, [{1,day},{1,hour}]}]}, header),
    {ok, {_, _, Res34}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{group, Group1}]}, header),
    {ok, {_, _, Res34}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{group, [Group1]}]}, header),
    {ok, {_, _, Res35}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{group, [Group1, Group2]}]}, header),
    {ok, {_, _, Res36}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{group, [Group1, wrong_group, Group2]}]}, header),
    %Evaluating results
    Req = fun(List) ->
        [Elem || Elem <- List, Elem == Inst1 orelse Elem == Inst2 orelse Elem == Inst3 orelse Elem == Inst4 orelse Elem == Inst5]
    end,
    true = length(Res01) < Count,                  % Checks if the constant enough for all the queries
    [I1,I2,I3] = Res00,
    [_,_,I1,I2,I3|_] = Res01,
    ?assertThat(Res01, contains_member(Inst1)),
    ?assertThat(Res01, contains_member(Inst2)),
    ?assertThat(Res01, contains_member(Inst3)),
    ?assertThat(Res01, contains_member(Inst4)),
    ?assertThat(Res01, contains_member(Inst5)),
    ?assertThat(Req(Res01), has_length(5)),
    ?assertThat(Res02, is([Inst1])),                % There should be only one instance with this id
    ?assertThat(Res03, is([Inst1])),                % There should be only one instance with this name
    ?assertThat(Req(Res04), is([Inst4])),
    ?assertThat(Res05, contains_member(Inst1)),
    ?assertThat(Res05, contains_member(Inst2)),
    ?assertThat(Res05, contains_member(Inst5)),
    ?assertThat(Req(Res05), has_length(3)),
    ?assertThat(Req(Res06), is([Inst2])),
    ?assertThat(Res07, contains_member(Inst1)),
    ?assertThat(Res07, contains_member(Inst3)),
    ?assertThat(Req(Res07), has_length(2)),
    ?assertThat(Res08, contains_member(Inst2)),
    ?assertThat(Res08, contains_member(Inst4)),
    ?assertThat(Res08, contains_member(Inst5)),
    ?assertThat(Req(Res08), has_length(3)),
    ?assertThat(Req(Res09), is([Inst2])),
    ?assertThat(Res10, contains_member(Inst2)),
    ?assertThat(Res10, contains_member(Inst4)),
    ?assertThat(Req(Res10), has_length(2)),
    ?assertThat(Res11, contains_member(Inst2)),
    ?assertThat(Res11, contains_member(Inst4)),
    ?assertThat(Res11, contains_member(Inst5)),
    ?assertThat(Req(Res11), has_length(3)),
    ?assertThat(Req(Res12), is([Inst4])),
    ?assertThat(Req(Res13), is([Inst4])),
    ?assertThat(Req(Res14), is([Inst5])),
    ?assertThat(Res15, contains_member(Inst1)),
    ?assertThat(Res15, contains_member(Inst2)),
    ?assertThat(Res15, contains_member(Inst3)),
    ?assertThat(Req(Res15), has_length(3)),
    ?assertThat(Req(Res16), is([Inst1])),
    ?assertThat(Res17, contains_member(Inst1)),
    ?assertThat(Res17, contains_member(Inst2)),
    ?assertThat(Req(Res17), has_length(2)),
    ?assertThat(Res18, contains_member(Inst1)),
    ?assertThat(Res18, contains_member(Inst2)),
    ?assertThat(Req(Res18), has_length(2)),
    ?assertThat(Res19, contains_member(Inst1)),
    ?assertThat(Res19, contains_member(Inst5)),
    ?assertThat(Req(Res19), has_length(2)),
    ?assertThat(Res20, contains_member(Inst1)),
    ?assertThat(Res20, contains_member(Inst5)),
    ?assertThat(Req(Res20), has_length(2)),
    ?assertThat(Res21, contains_member(Inst2)),
    ?assertThat(Res21, contains_member(Inst4)),
    ?assertThat(Req(Res21), has_length(2)),
    ?assertThat(Res22, contains_member(Inst2)),
    ?assertThat(Res22, contains_member(Inst4)),
    ?assertThat(Req(Res22), has_length(2)),
    ?assertThat(Res23, contains_member(Inst2)),
    ?assertThat(Res23, contains_member(Inst4)),
    ?assertThat(Req(Res23), has_length(2)),
    ?assertThat(Res24, contains_member(Inst2)),
    ?assertThat(Res24, contains_member(Inst4)),
    ?assertThat(Req(Res24), has_length(2)),
    ?assertThat(Res25, contains_member(Inst2)),
    ?assertThat(Res25, contains_member(Inst4)),
    ?assertThat(Req(Res25), has_length(2)),
    ?assertThat(Res26, contains_member(Inst2)),
    ?assertThat(Res26, contains_member(Inst4)),
    ?assertThat(Req(Res26), has_length(2)),
    ?assertThat(Res27, contains_member(Inst3)),
    ?assertThat(Res27, contains_member(Inst4)),
    ?assertThat(Req(Res27), has_length(2)),
    ?assertThat(Res28, contains_member(Inst3)),
    ?assertThat(Res28, contains_member(Inst4)),
    ?assertThat(Req(Res28), has_length(2)),
    ?assertThat(Res29, contains_member(Inst3)),
    ?assertThat(Res29, contains_member(Inst5)),
    ?assertThat(Req(Res29), has_length(2)),
    ?assertThat(Res30, contains_member(Inst3)),
    ?assertThat(Res30, contains_member(Inst5)),
    ?assertThat(Req(Res30), has_length(2)),
    ?assertThat(Res31, contains_member(Inst1)),
    ?assertThat(Res31, contains_member(Inst5)),
    ?assertThat(Req(Res31), has_length(2)),
    ?assertThat(Res32, contains_member(Inst1)),
    ?assertThat(Res32, contains_member(Inst2)),
    ?assertThat(Res32, contains_member(Inst5)),
    ?assertThat(Req(Res32), has_length(3)),
    ?assertThat(Res33, contains_member(Inst1)),
    ?assertThat(Res33, contains_member(Inst3)),
    ?assertThat(Req(Res33), has_length(2)),
    ?assertThat(Res34, contains_member(Inst1)),
    ?assertThat(Res34, contains_member(Inst2)),
    ?assertThat(Req(Res34), has_length(2)),
    ?assertThat(Res35, contains_member(Inst1)),
    ?assertThat(Res35, contains_member(Inst2)),
    ?assertThat(Res35, contains_member(Inst5)),
    ?assertThat(Req(Res35), has_length(3)),
    ?assertThat(Res36, contains_member(Inst1)),
    ?assertThat(Res36, contains_member(Inst2)),
    ?assertThat(Res36, contains_member(Inst5)),
    ?assertThat(Req(Res36), has_length(3)),
    % Performing sucessful compound tests
    {ok, {_, _, Res50}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, IID1},{name, testing_name}]}, header),
    {ok, {_, _, Res51}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, {12,hour}},{id, IID1}]}, header),
    {ok, {_, _, Res52}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{created, OldDate2, undefined},{tag, [{<<"123">>, <<"cust_nr">>}]}]}, header),
    {ok, {_, _, Res53}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, {12,hour}},{created, OldDate2, undefined}]}, header),
    {ok, {_, _, Res54}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{last_trn_age, {12,hour}}, {age, {12,hour}}, {age, [{1,day},{1,hour}]}, {last_trn_age, [{2,day},{1,hour}]}]}, header),
    {ok, {_, _, Res55}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{created, undefined, OldDate2}, {group, Group1}]}, header),
    % Evaluating results
    ?assertThat(Req(Res50), is([Inst1])),
    ?assertThat(Req(Res51), is([Inst1])),
    ?assertThat(Res52, contains_member(Inst2)),
    ?assertThat(Res52, contains_member(Inst4)),
    ?assertThat(Req(Res52), has_length(2)),
    ?assertThat(Req(Res53), is([Inst2])),
    ?assertThat(Req(Res54), is([Inst1])),
    ?assertThat(Req(Res55), is([Inst1])),
    % Performing empty list tests
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, non_existent_id}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{name, non_existent_name}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, IID3},{name, testing_name}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{module, some_other_fsm}, {module, [another_fsm]}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{status, [resuming]}, {status, killed}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{id, []}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{name, []}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{tag, []}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{module, []}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{status, []}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{age, {12,hour}},{created, OldDate2, undefined},{last_trn_age, {12,hour}}]}, header),
    {ok, {0, _, []}} = eproc_store:get_instance(Store, {filter, {From, Count}, [{group, Group1},{group, Group2}]}, header),
    % Performing sort tests
    {ok, {_, _, Res90}} = eproc_store:get_instance(Store, {filter, {From, Count, id}, []}, header),
    {ok, {_, _, Res91}} = eproc_store:get_instance(Store, {filter, {From, Count, name}, []}, header),
    {ok, {_, _, Res01}} = eproc_store:get_instance(Store, {filter, {From, Count, last_trn}, []}, header),
    {ok, {_, _, Res93}} = eproc_store:get_instance(Store, {filter, {From, Count, created}, []}, header),
    {ok, {_, _, Res94}} = eproc_store:get_instance(Store, {filter, {From, Count, module}, []}, header),
    {ok, {_, _, Res95}} = eproc_store:get_instance(Store, {filter, {From, Count, status}, []}, header),
    {ok, {_, _, Res96}} = eproc_store:get_instance(Store, {filter, {From, Count, age}, []}, header),
    % Evaluating results
    ?assertThat(Req(Res90), is([Inst1, Inst2, Inst3, Inst4, Inst5])),
    [Inst5, Inst1 | RestRes91] = Req(Res91),
    ?assertThat(RestRes91, contains_member(Inst2)),
    ?assertThat(RestRes91, contains_member(Inst3)),
    ?assertThat(RestRes91, contains_member(Inst4)),
    ?assertThat(RestRes91, has_length(3)),
    ?assertThat(Req(Res01), is([Inst5, Inst1, Inst2, Inst4, Inst3])),
    [Inst5, Inst4, Inst2 | RestRes93] = Req(Res93),
    ?assertThat(RestRes93, contains_member(Inst1)),
    ?assertThat(RestRes93, contains_member(Inst3)),
    ?assertThat(RestRes93, has_length(2)),
    [Inst3, RestRes941, RestRes942, RestRes943, Inst4] = Req(Res94),
    RestRes94 = [RestRes941, RestRes942, RestRes943],
    ?assertThat(RestRes94, contains_member(Inst1)),
    ?assertThat(RestRes94, contains_member(Inst2)),
    ?assertThat(RestRes94, contains_member(Inst5)),
    [Inst3, Inst5 | RestRes95] = Req(Res95),
    ?assertThat(RestRes95, contains_member(Inst1)),
    ?assertThat(RestRes95, contains_member(Inst2)),
    ?assertThat(RestRes95, contains_member(Inst4)),
    ?assertThat(Req(Res96), is([Inst1, Inst3, Inst2, Inst4, Inst5])),
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
    MsgId11 = {IID1, 1, 0, recv},
    MsgId12 = {IID1, 1, 1, sent},
    MsgId13 = {IID1, 1, 2, recv},
    Trn1 = #transition{
        trn_id = 1,
        sname = [s1],
        sdata = d1,
        timestamp = os:timestamp(),
        duration = 13,
        trn_node = undefined,
        trigger_type = event,
        trigger_msg = #msg_ref{cid = MsgId11, peer = {connector, some}, type = <<"some_type">>},
        trigger_resp = #msg_ref{cid = MsgId12, peer = {connector, some}},
        trn_messages = [#msg_ref{cid = MsgId13, peer = {connector, some}}],
        attr_last_nr = 1,
        attr_actions = [#attr_action{module = m, attr_nr = 1, action = {create, undefined, [], some}}],
        inst_status = running,
        interrupts = undefined
    },
    Msg11 = #message{msg_id = MsgId11, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m11, type = <<"some_type">>},
    Msg12 = #message{msg_id = MsgId12, sender = {connector, some}, receiver = {inst, IID1}, resp_to = MsgId11,   date = os:timestamp(), body = m12},
    Msg13 = #message{msg_id = MsgId13, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m13},
    {ok, IID1, 1} = eproc_store:add_transition(Store, IID1, Trn1, [Msg11, Msg12, Msg13]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 1, sname = [s1], sdata = d1, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add another ordinary transition
    MsgId2 = {IID1, 2, 0, recv},
    Trn2 = Trn1#transition{
        trn_id = 2,
        sname = [s2],
        sdata = d2,
        trigger_msg = #msg_ref{cid = MsgId2, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = []
    },
    Msg21 = #message{msg_id = MsgId2, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m21},
    {ok, IID1, 2} = eproc_store:add_transition(Store, IID1, Trn2, [Msg21]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 2, sname = [s2], sdata = d2, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Suspend by transition.
    MsgId3 = {IID1, 3, 0, recv},
    Trn3 = Trn1#transition{
        trn_id = 3,
        sname = [s3],
        sdata = d3,
        trigger_msg = #msg_ref{cid = MsgId3, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = suspended,
        interrupts = [#interrupt{reason = {fault, some_reason}}]
    },
    Msg31 = #message{msg_id = MsgId3, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m31},
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
    MsgId4 = {IID1, 4, 0, recv},
    Trn4 = Trn1#transition{
        trn_id = 4,
        sname = [s4],
        sdata = d4,
        trigger_msg = #msg_ref{cid = MsgId4, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg41 = #message{msg_id = MsgId4, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m41},
    {ok, IID1, 4} = eproc_store:add_transition(Store, IID1, Trn4, [Msg41]),
    {ok, #instance{status = running, interrupt = undefined, curr_state = #inst_state{
        stt_id = 4, sname = [s4], sdata = d4, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Terminate FSM.
    MsgId5 = {IID1, 5, 0, recv},
    Trn5 = Trn1#transition{
        trn_id = 5,
        sname = [s5],
        sdata = d5,
        trigger_msg = #msg_ref{cid = MsgId5, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = completed,
        interrupts = undefined
    },
    Msg51 = #message{msg_id = MsgId5, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m51},
    {ok, IID1, 5} = eproc_store:add_transition(Store, IID1, Trn5, [Msg51]),
    {ok, #instance{status = completed, interrupt = undefined, curr_state = #inst_state{
        stt_id = 5, sname = [s5], sdata = d5, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Add transition to the terminated FSM.
    MsgId6 = {IID1, 6, 0, recv},
    Trn6 = Trn1#transition{
        trn_id = 6,
        sname = [s6],
        sdata = d6,
        trigger_msg = #msg_ref{cid = MsgId6, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [],
        inst_status = running,
        interrupts = undefined
    },
    Msg61 = #message{msg_id = MsgId6, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m61},
    {error, terminated} = eproc_store:add_transition(Store, IID1, Trn6, [Msg61]),
    {ok, #instance{status = completed, interrupt = undefined, curr_state = #inst_state{
        stt_id = 5, sname = [s5], sdata = d5, timestamp = {_, _, _},
        attr_last_nr = 1, attrs_active = [_]
    }}} = eproc_store:get_instance(Store, {inst, IID1}, current),
    %%
    %%  Check if message is returned correctly, including message type.
    {ok, #message{type = <<"some_type">>}} = eproc_store:get_message(Store, MsgId11, all),
    {ok, #transition{trigger_msg = #msg_ref{type = <<"some_type">>}}} = eproc_store:get_transition(Store, {inst, IID1}, 1, all),
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
    %%  Some constants.
    Now = os:timestamp(),
    OldDate1 = eproc_timer:timestamp_before({3,day}, Now),
    OldDate2 = eproc_timer:timestamp_before({2,day}, Now),
    OldDate3 = eproc_timer:timestamp_before({1,day}, Now),
    OldDate4 = eproc_timer:timestamp_before({12,hour}, Now),
    %%  Add instances.
    Inst = inst_value(),
    {ok, IID1} = eproc_store:add_instance(Store, Inst),
    {ok, IID2} = eproc_store:add_instance(Store, Inst),
    {ok, IID3} = eproc_store:add_instance(Store, Inst),
    {ok, NodeRef} = eproc_store:get_node(Store),
    %%  Add transitions.
    Msg1r = #message{msg_id = {IID1, 1, 0, recv}, sender = {ext, some},  receiver = {inst, IID1},      resp_to = undefined, date = OldDate1,       body = m1},
    Msg2s = #message{msg_id = {IID1, 1, 2, sent}, sender = {inst, IID1}, receiver = {inst, undefined}, resp_to = undefined, date = OldDate3,       body = m2},
    Msg2r = #message{msg_id = {IID1, 1, 2, recv}, sender = {inst, IID1}, receiver = {inst, IID2},      resp_to = undefined, date = OldDate3,       body = m2},
    Msg3r = #message{msg_id = {IID1, 1, 3, recv}, sender = {inst, IID1}, receiver = {inst, IID2},      resp_to = undefined, date = Now,            body = m3},
    Msg4r = #message{msg_id = {IID2, 1, 1, recv}, sender = {inst, IID2}, receiver = {inst, IID3},      resp_to = undefined, date = os:timestamp(), body = m4},
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
    Trn4 = Trn1#transition{
        trn_id = 1,
        trigger_msg = #msg_ref{cid = {IID2, 1, 1, recv}, peer = {inst, IID2}},
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
    {ok, IID3, 1} = eproc_store:add_transition(Store, IID3, Trn4, [Msg4r]),
    %%  Get the stored data.
    Msg1 = Msg1r#message{msg_id = {IID1, 1, 0}},
    Msg2 = Msg2r#message{msg_id = {IID1, 1, 2}}, %% Receiver = {inst, IID2}
    Msg3 = Msg3r#message{msg_id = {IID1, 1, 3}},
    Msg4 = Msg4r#message{msg_id = {IID2, 1, 1}},
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 0      }, all), is({ok, Msg1})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 0, sent}, all), is({error, not_found})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 0, recv}, all), is({ok, Msg1})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 2      }, all), is({ok, Msg2})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 2, sent}, all), is({ok, Msg2})), % Receiver resolved.
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 2, recv}, all), is({ok, Msg2})),
    ?assertThat(eproc_store:get_message(Store, {IID1, 1, 1      }, all), is({error, not_found})),
    ?assertThat(eproc_store:get_transition(Store, {inst, IID1}, 1, all), is({ok, Trn1Fix})),
    ?assertThat(eproc_store:get_transition(Store, {inst, IID2}, 1, all), is({ok, Trn2Fix})),
    ?assertThat(eproc_store:get_transition(Store, {inst, IID2}, 3, all), is({error, not_found})),
    {ok, {1, true, Trns1a}} = eproc_store:get_transition(Store, {inst, IID1}, {list, 1,       100}, all),
    {ok, {1, true, Trns1b}} = eproc_store:get_transition(Store, {inst, IID1}, {list, 1,       0  }, all),
    {ok, {2, true, Trns2a}} = eproc_store:get_transition(Store, {inst, IID2}, {list, current, 100}, all),
    {ok, {2, true, Trns2a}} = eproc_store:get_transition(Store, {inst, IID2}, {list, 0,       100}, all),
    {ok, {2, true, Trns2b}} = eproc_store:get_transition(Store, {inst, IID2}, {list, current, 1  }, all),
    {ok, {2, true, Trns2c}} = eproc_store:get_transition(Store, {inst, IID2}, {list, -1,      100}, all),
    ?assertThat(Trns1a, has_length(1)),
    ?assertThat(Trns1b, has_length(0)),
    ?assertThat(Trns2a, has_length(2)),
    ?assertThat(Trns2b, has_length(1)),
    ?assertThat(Trns2c, has_length(1)),
    %% Test get_message list
    ?assertThat(eproc_store:get_message(Store, {list, []}, all), is({ok, []})),
    ?assertThat(eproc_store:get_message(Store, {list, [{IID1, 1, 0      }]}, all), is({ok, [Msg1]})),
    ?assertThat(eproc_store:get_message(Store, {list, [{IID1, 1, 0, sent}]}, all), is({error, not_found})),
    ?assertThat(eproc_store:get_message(Store, {list, [{IID1, 1, 0, recv}]}, all), is({ok, [Msg1]})),
    ?assertThat(eproc_store:get_message(Store, {list, [{IID1, 1, 0, sent}, {IID1, 1, 0      }]}, all), is({error, not_found})),
    ?assertThat(eproc_store:get_message(Store, {list, [{IID1, 1, 0      }, {IID1, 1, 2, recv}]}, all), is({ok, [Msg1, Msg2]})),
    ?assertThat(eproc_store:get_message(Store, {list, [{IID1, 1, 3, recv}, {IID1, 1, 0, recv}, {IID1, 1, 2}]}, all), is({ok, [Msg3, Msg1, Msg2]})),
    % Performing sucessful simple get_message filter tests
    From = 1,
    Count = 99,
    {ok, {_, _, Res00}} = eproc_store:get_message(Store, {filter, {From+1, 3}, []}, all),
    {ok, {_, _, Res01}} = eproc_store:get_message(Store, {filter, {From, Count}, []}, all),
    {ok, {_, _, Res02}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, {IID1, 1, 3, recv}}]}, all),
    {ok, {_, _, Res02}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, {IID1, 1, 3, sent}}]}, all),
    {ok, {_, _, Res02}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, {IID1, 1, 3      }}]}, all),
    {ok, {_, _, Res03}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, [{IID1, 1, 2, recv}, {IID2, 1, 1, sent}]}]}, all),
    {ok, {_, _, Res04}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, [{IID1, 1, 2, sent}, {non, existent, id}, {IID2, 1, 1}]}]}, all),
    {ok, {_, _, Res05}} = eproc_store:get_message(Store, {filter, {From, Count}, [{date, undefined, OldDate4}]}, all),
    {ok, {_, _, Res06}} = eproc_store:get_message(Store, {filter, {From, Count}, [{date, OldDate2, undefined}]}, all),
    {ok, {_, _, Res07}} = eproc_store:get_message(Store, {filter, {From, Count}, [{date, OldDate2, OldDate4}]}, all),
    {ok, {_, _, Res08}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, {sender, {inst, IID1}}}]}, all),
    {ok, {_, _, Res09}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, {receiver, {inst, IID1}}}]}, all),
    {ok, {_, _, Res10}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, {any,  {inst, IID1}}}]}, all),
    {ok, {_, _, Res11}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{any, {inst, IID1}}]}]}, all),
    {ok, {_, _, Res12}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{sender,   {inst, IID2}}, {sender,   {inst, IID3}}]}]}, all),
    {ok, {_, _, Res13}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{receiver, {inst, IID2}}, {receiver, {inst, IID3}}]}]}, all),
    {ok, {_, _, Res14}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{any,      {inst, IID2}}, {any,      {inst, IID3}}]}]}, all),
    {ok, {_, _, Res15}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{sender,   {inst, IID1}}, {receiver, {inst, IID3}}]}]}, all),
    {ok, {_, _, Res16}} = eproc_store:get_message(Store, {filter, {From, Count}, [{age, {12,hour}}]}, all),
    {ok, {_, _, Res16}} = eproc_store:get_message(Store, {filter, {From, Count}, [{age, {12,hour}}, {age, [{2,day},{1,hour}]}]}, all),
    {ok, {_, _, Res17}} = eproc_store:get_message(Store, {filter, {From, Count}, [{age, [{2,day},{1,hour}]}]}, all),
    %Evaluating results
    Req = fun(List) ->
        [Elem || Elem <- List, Elem == Msg1 orelse Elem == Msg2 orelse Elem == Msg3 orelse Elem == Msg4]
    end,
    true = length(Res01) < Count,                  % Checks if the constant enough for all the queries
    [M1,M2,M3] = Res00,
    [_,M1,M2,M3|_] = Res01,
    ?assertThat(Req(Res02), is([Msg3])),
    ?assertThat(Res03, contains_member(Msg2)),
    ?assertThat(Res03, contains_member(Msg4)),
    ?assertThat(Req(Res03), has_length(2)),
    ?assertThat(Res04, contains_member(Msg2)),
    ?assertThat(Res04, contains_member(Msg4)),
    ?assertThat(Req(Res04), has_length(2)),
    ?assertThat(Res05, contains_member(Msg1)),
    ?assertThat(Res05, contains_member(Msg2)),
    ?assertThat(Req(Res05), has_length(2)),
    ?assertThat(Res06, contains_member(Msg2)),
    ?assertThat(Res06, contains_member(Msg3)),
    ?assertThat(Res06, contains_member(Msg4)),
    ?assertThat(Req(Res06), has_length(3)),
    ?assertThat(Req(Res07), is([Msg2])),
    ?assertThat(Res08, contains_member(Msg2)),
    ?assertThat(Res08, contains_member(Msg3)),
    ?assertThat(Req(Res08), has_length(2)),
    ?assertThat(Req(Res09), is([Msg1])),
    ?assertThat(Res10, contains_member(Msg1)),
    ?assertThat(Res10, contains_member(Msg2)),
    ?assertThat(Res10, contains_member(Msg3)),
    ?assertThat(Req(Res10), has_length(3)),
    ?assertThat(Res11, contains_member(Msg1)),
    ?assertThat(Res11, contains_member(Msg2)),
    ?assertThat(Res11, contains_member(Msg3)),
    ?assertThat(Req(Res11), has_length(3)),
    ?assertThat(Req(Res12), is([Msg4])),
    ?assertThat(Res13, contains_member(Msg2)),
    ?assertThat(Res13, contains_member(Msg3)),
    ?assertThat(Res13, contains_member(Msg4)),
    ?assertThat(Req(Res13), has_length(3)),
    ?assertThat(Res14, contains_member(Msg2)),
    ?assertThat(Res14, contains_member(Msg3)),
    ?assertThat(Res14, contains_member(Msg4)),
    ?assertThat(Req(Res14), has_length(3)),
    ?assertThat(Res15, contains_member(Msg2)),
    ?assertThat(Res15, contains_member(Msg3)),
    ?assertThat(Res15, contains_member(Msg4)),
    ?assertThat(Req(Res15), has_length(3)),
    ?assertThat(Res16, contains_member(Msg3)),
    ?assertThat(Res16, contains_member(Msg4)),
    ?assertThat(Req(Res16), has_length(2)),
    ?assertThat(Res17, contains_member(Msg2)),
    ?assertThat(Res17, contains_member(Msg3)),
    ?assertThat(Res17, contains_member(Msg4)),
    ?assertThat(Req(Res17), has_length(3)),
    % Performing sucessful compound tests
    {ok, {_, _, Res50}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, {IID1, 1, 2, recv}}, {id, {IID1, 1, 2, sent}}]}, all),
    {ok, {_, _, Res51}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, {sender, {inst,IID1}}}, {date, undefined, OldDate4}]}, all),
    {ok, {_, _, Res52}} = eproc_store:get_message(Store, {filter, {From, Count}, [{date, undefined, OldDate4}, {peer, {sender, {inst,IID1}}}]}, all),
    {ok, {_, _, Res53}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, [{IID1, 1, 2}, {IID1, 1, 3}]}, {date, OldDate4, undefined}]}, all),
    {ok, {_, _, Res54}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{sender, {inst,IID2}},{receiver, {inst,IID2}}]}, {peer, {any, {inst,IID3}}}]}, all),
    {ok, {_, _, Res55}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, [{any, {inst, IID1}}]}, {age, [{2,day},{1,hour}]}]}, all),
    %Evaluating results
    ?assertThat(Req(Res50), is([Msg2])),
    ?assertThat(Req(Res51), is([Msg2])),
    ?assertThat(Req(Res52), is([Msg2])),
    ?assertThat(Req(Res53), is([Msg3])),
    ?assertThat(Req(Res54), is([Msg4])),
    ?assertThat(Res55, contains_member(Msg2)),
    ?assertThat(Res55, contains_member(Msg3)),
    ?assertThat(Req(Res55), has_length(2)),
    % Performing empty list tests
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, {non, existent, id}}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, {IID1, 1, 2}}, {id, {IID1, 1, 3, sent}}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, {sender, {inst,IID2}}}, {date, undefined, OldDate4}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, [{IID1, 1, 2}, {IID1, 1, 3}]}, {date, undefined, OldDate2}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{date, undefined, OldDate2}, {id, [{IID1, 1, 2}, {IID1, 1, 3}]}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{id, []}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{peer, []}]}, all),
    {ok, {0, _, []}} = eproc_store:get_message(Store, {filter, {From, Count}, [{age, {12,hour}}, {date, OldDate2, OldDate4}, {age, [{2,day},{1,hour}]}]}, all),
    % Performing sort tests
    {ok, {_, _, Res90}} = eproc_store:get_message(Store, {filter, {From, Count, id}, []}, all),
    {ok, {_, _, Res01}} = eproc_store:get_message(Store, {filter, {From, Count, date}, []}, all),
    {ok, {_, _, Res91}} = eproc_store:get_message(Store, {filter, {From, Count, sender}, []}, all),
    {ok, {_, _, Res92}} = eproc_store:get_message(Store, {filter, {From, Count, receiver}, []}, all),
    % Evaluating results
    case IID1 < IID2 of
        true ->
            ?assertThat(Req(Res90), is([Msg1, Msg2, Msg3, Msg4])),
            [Msg1, RestRes911, RestRes912, Msg4] = Req(Res91),
            RestRes91 = [RestRes911, RestRes912],
            ?assertThat(RestRes91, contains_member(Msg2)),
            ?assertThat(RestRes91, contains_member(Msg3));
        false ->
            ?assertThat(Req(Res90), is([Msg4, Msg1, Msg2, Msg3])),
            [Msg1, Msg4 | RestRes91] = Req(Res91),
            ?assertThat(RestRes91, contains_member(Msg2)),
            ?assertThat(RestRes91, contains_member(Msg3)),
            ?assertThat(RestRes91, has_length(2))
    end,
    ?assertThat(Req(Res01), is([Msg4, Msg3, Msg2, Msg1])),
    RestRes92 = case lists:usort([IID1, IID2, IID3]) of
        [IID1, IID2, IID3] ->
            [Msg1, RestRes921, RestRes922, Msg4] = Req(Res92),
            [RestRes921, RestRes922];
        [IID1, IID3, IID2] ->
            [Msg1, Msg4 | RestRes92_] = Req(Res92),
            RestRes92_;
        [IID2, IID1, IID3] ->
            [RestRes921, RestRes922, Msg1, Msg4] = Req(Res92),
            [RestRes921, RestRes922];
        [IID2, IID3, IID1] ->
            [RestRes921, RestRes922, Msg4, Msg1] = Req(Res92),
            [RestRes921, RestRes922];
        [IID3, IID1, IID2] ->
            [Msg4, Msg1 | RestRes92_] = Req(Res92),
            RestRes92_;
        [IID3, IID2, IID1] ->
            [Msg4, RestRes921, RestRes922, Msg1] = Req(Res92),
            [RestRes921, RestRes922]
    end,
    ?assertThat(RestRes92, contains_member(Msg2)),
    ?assertThat(RestRes92, contains_member(Msg3)),
    ?assertThat(RestRes92, has_length(2)),
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
    %   Check bad scenarios.
    {error, not_found} = eproc_store:get_state(Store, {inst, IID}, 6, all),
    {error, not_found} = eproc_store:get_state(Store, {inst, IID}, {list, 6, 17}, all),
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
    MsgId1 = {IID1, 1, 0, recv},
    Trn1 = #transition{
        trn_id = 1, sname = [s1], sdata = d1,
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId1, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = m, attr_nr = 1, needs_store = false, action = {create, n11, [], some}}
        ],
        inst_status = running,interrupts = undefined
    },
    Msg11 = #message{msg_id = MsgId1, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m11},
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
    MsgId2 = {IID1, 2, 0, recv},
    Trn2 = Trn1#transition{
        trn_id = 2,
        sname = [s2],
        sdata = d2,
        trigger_msg = #msg_ref{cid = MsgId2, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_actions = [
            #attr_action{module = m2, attr_nr = 2, needs_store = true, action = {create, n11, [], some}}
        ]
    },
    Msg21 = #message{msg_id = MsgId2, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m21},
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
    Now = os:timestamp(),
    Key1 = {eproc_store_router_test_attrs, {Now, 1}},
    Key2 = {eproc_store_router_test_attrs, {Now, 2}},
    Key3 = {eproc_store_router_test_attrs, {Now, 3}},  % Non-unique key.
    RouterOpts = [{store, Store}],
    %%
    %%  Add instances.
    %%
    {ok, IID1} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID2} = eproc_store:add_instance(Store, inst_value()),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key3, RouterOpts), is({ok, []})),
    %%
    %%  Add a key synchronously.
    %%
    {ok, SyncRef} = eproc_store:attr_task(Store, eproc_router, {key_sync, Key2, IID1, false}),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(Key3, RouterOpts), is({ok, []})),
    %%
    %%  Add the key attributes.
    %%
    % First instance.
    MsgId111 = {IID1, 1, 0, recv},
    Trn11 = #transition{
        trn_id = 1, sname = [s1], sdata = d1,
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId111, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {create, undefined, [s1], {data, Key1, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 2, needs_store = true, action = {create, undefined, [],   {data, Key2, SyncRef}}},
            #attr_action{module = eproc_router, attr_nr = 3, needs_store = true, action = {create, undefined, [],   {data, Key3, undefined}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg111 = #message{msg_id = MsgId111, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m111},
    {ok, IID1, 1} = eproc_store:add_transition(Store, IID1, Trn11, [Msg111]),
    % Second instance.
    MsgId211 = {IID2, 1, 0, recv},
    Trn21 = #transition{
        trn_id = 1, sname = [s1], sdata = d1,
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId211, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {create, undefined, [], {data, Key3, undefined}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg211 = #message{msg_id = MsgId211, sender = {connector, some}, receiver = {inst, IID2}, resp_to = undefined, date = os:timestamp(), body = m211},
    {ok, IID2, 1} = eproc_store:add_transition(Store, IID2, Trn21, [Msg211]),
    %
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID1]})),
    {ok, Key3IDs} = eproc_router:lookup(Key3, RouterOpts),
    SortedKey3IDs = lists:sort([IID1, IID2]),
    SortedKey3IDs = lists:sort(Key3IDs),
    %%
    %%  Remove one attr by scope.
    %%
    MsgId121 = {IID1, 2, 0, recv},
    Trn12 = Trn11#transition{
        trn_id = 2, sname = [s2], sdata = d2,
        trigger_msg = #msg_ref{cid = MsgId121, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 2,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {remove, {scope, [s2]}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg121 = #message{msg_id = MsgId121, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m11},
    {ok, IID1, 2} = eproc_store:add_transition(Store, IID1, Trn12, [Msg121]),
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID1]})),
    %%
    %% Check, if taks are available after instance is terminated.
    ?assertThat(eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}), is({ok, IID1})),
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(Key3, RouterOpts), is({ok, [IID2]})),
    ?assertThat(eproc_store:set_instance_killed(Store, {inst, IID2}, #user_action{}), is({ok, IID2})),
    ?assertThat(eproc_router:lookup(Key3, RouterOpts), is({ok, []})),
    ok.


%%
%%  Check if store operations for adding/removing same `eproc_router` keys to different instances work.
%%
eproc_store_router_test_multiple(Config) ->
    %
    % Initialisation
    Store = store(Config),
    Now = os:timestamp(),
    KeyAsync = {eproc_store_router_test_multiple, {Now, asynchronous}},             % Asynchronous [non unique] key
    KeySyncM = {eproc_store_router_test_multiple, {Now, synchronous_multiple}},     % Synchronous non unique key
    KeySyncU = {eproc_store_router_test_multiple, {Now, synchronous_unique}},       % Synchronous unique key
    KeySyAsy = {eproc_store_router_test_multiple, {Now, synchronous_asynchronous}}, % Key, that is added both synchronously and asynchronously
    RouterOpts = [{store, Store}],
    {ok, IID1} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID2} = eproc_store:add_instance(Store, inst_value()),
    IID12Sorted = lists:sort([IID1, IID2]),
    ?assertThat(eproc_router:lookup(KeyAsync, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(KeySyncM, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, []})),
    %
    % Adding keys synchronously.
    {ok, SyncRefM1} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncM, IID1, false}),    % Adding synchronous non unique key to instance 1
    {ok, SyncRefM2} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncM, IID2, false}),    % Adding synchronous non unique key to instance 2
    {ok, undefined} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncM, IID1, false}),    % Updating synchronous non unique key of instance 1
    {ok, SyncRefU1} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncU, IID1, true}),     % Adding synchronous unique key to instance 1
    {error, exists} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncU, IID2, true}),     % Adding synchronous unique key to instance 2 -> fail
    {ok, undefined} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncU, IID1, true}),     % Updating synchronous unique key of instance 1
    {ok, SyncRefSA} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyAsy, IID1, false}),    % Adding synchronous-asynchronous key synchronously
    ?assertThat(eproc_router:lookup(KeyAsync, RouterOpts), is({ok, []})),
    {ok, Res1}= eproc_router:lookup(KeySyncM, RouterOpts),
    ?assertThat(lists:sort(Res1),                          is(IID12Sorted)),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(KeySyAsy, RouterOpts), is({ok, [IID1]})),
    %
    % Adding the key attributes.
    %
    % First instance.
    MsgId111 = {IID1, 1, 0, recv},
    Trn11 = #transition{
        trn_id = 1, sname = s1, sdata = {data, 1, 1},
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId111, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {create, KeySyncM, '_', {data, KeySyncM, SyncRefM1}}},
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {update,           s1,  {data, KeySyncM, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 2, needs_store = true, action = {create, KeySyncU, s1,  {data, KeySyncU, SyncRefU1}}},
            #attr_action{module = eproc_router, attr_nr = 3, needs_store = true, action = {create, KeyAsync, '_', {data, KeyAsync, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 2, needs_store = true, action = {update,           '_', {data, KeySyncU, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 3, needs_store = true, action = {update,           '_', {data, KeyAsync, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 4, needs_store = true, action = {create, KeySyAsy, '_', {data, KeySyAsy, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 4, needs_store = true, action = {update,           '_', {data, KeySyAsy, SyncRefSA}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg111 = #message{msg_id = MsgId111, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m111},
    {ok, IID1, 1} = eproc_store:add_transition(Store, IID1, Trn11, [Msg111]),
    % Second instance.
    MsgId211 = {IID2, 1, 0, recv},
    Trn21 = #transition{
        trn_id = 1, sname = s1, sdata = {data, 2, 1},
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId211, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 1,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {create, KeySyncM, '_', {data, KeySyncM, SyncRefM2}}},
            #attr_action{module = eproc_router, attr_nr = 2, needs_store = true, action = {create, KeyAsync, '_', {data, KeyAsync, undefined}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg211 = #message{msg_id = MsgId211, sender = {connector, some}, receiver = {inst, IID2}, resp_to = undefined, date = os:timestamp(), body = m211},
    {ok, IID2, 1} = eproc_store:add_transition(Store, IID2, Trn21, [Msg211]),
    % Testing results
    {ok, Res2}= eproc_router:lookup(KeyAsync, RouterOpts),
    ?assertThat(lists:sort(Res2),                          is(IID12Sorted)),
    {ok, Res3}= eproc_router:lookup(KeySyncM, RouterOpts),
    ?assertThat(lists:sort(Res3),                          is(IID12Sorted)),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(KeySyAsy, RouterOpts), is({ok, [IID1]})),
    %
    % Removing one attribute by scope.
    MsgId121 = {IID1, 2, 0, recv},
    Trn12 = Trn11#transition{
        trn_id = 2, sname = s2, sdata = {data, 1, 2},
        trigger_msg = #msg_ref{cid = MsgId121, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 2,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {remove, {scope, s2}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg121 = #message{msg_id = MsgId121, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m11},
    {ok, IID1, 2} = eproc_store:add_transition(Store, IID1, Trn12, [Msg121]),
    {ok, Res4}= eproc_router:lookup(KeyAsync, RouterOpts),
    ?assertThat(lists:sort(Res4),                          is(IID12Sorted)),
    ?assertThat(eproc_router:lookup(KeySyncM, RouterOpts), is({ok, [IID2]})),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(KeySyAsy, RouterOpts), is({ok, [IID1]})),
    %
    % Adding keys synchronously once again
    {ok, SyncRefM3} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncM, IID1, false}),    % Adding synchronous non unique key to instance 1 (after removal)
    {ok, undefined} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncM, IID2, false}),    % Updating synchronous non unique key of instance 2
    {error, exists} = eproc_store:attr_task(Store, eproc_router, {key_sync, KeySyncU, IID2, true}),     % Adding synchronous unique key to instance 2 -> fail
    {ok, Res5}= eproc_router:lookup(KeyAsync, RouterOpts),
    ?assertThat(lists:sort(Res5),                          is(IID12Sorted)),
    {ok, Res6}= eproc_router:lookup(KeySyncM, RouterOpts),
    ?assertThat(lists:sort(Res6),                          is(IID12Sorted)),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(KeySyAsy, RouterOpts), is({ok, [IID1]})),
    %
    % Adding key attributes once again
    %
    % First instance.
    MsgId131 = {IID1, 1, 0, recv},
    Trn13 = #transition{
        trn_id = 3, sname = s3, sdata = {data, 1, 3},
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId131, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 2,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 5, needs_store = true, action = {create, KeySyncM, '_', {data, KeySyncM, SyncRefM3}}},
            #attr_action{module = eproc_router, attr_nr = 3, needs_store = true, action = {update,           s3,  {data, KeyAsync, undefined}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg131 = #message{msg_id = MsgId131, sender = {connector, some}, receiver = {inst, IID1}, resp_to = undefined, date = os:timestamp(), body = m131},
    {ok, IID1, 3} = eproc_store:add_transition(Store, IID1, Trn13, [Msg131]),
    % Second instance.
    MsgId231 = {IID2, 1, 0, recv},
    Trn23 = #transition{
        trn_id = 2, sname = s3, sdata = {data, 2, 3},
        timestamp = os:timestamp(), duration = 13, trigger_type = event,
        trn_node = undefined,
        trigger_msg = #msg_ref{cid = MsgId231, peer = {connector, some}},
        trigger_resp = undefined,
        trn_messages = [],
        attr_last_nr = 3,
        attr_actions = [
            #attr_action{module = eproc_router, attr_nr = 1, needs_store = true, action = {update, s3,  {data, KeySyncM, undefined}}},
            #attr_action{module = eproc_router, attr_nr = 2, needs_store = true, action = {update, s3,  {data, KeyAsync, undefined}}}
        ],
        inst_status = running, interrupts = undefined
    },
    Msg231 = #message{msg_id = MsgId231, sender = {connector, some}, receiver = {inst, IID2}, resp_to = undefined, date = os:timestamp(), body = m221},
    {ok, IID2, 2} = eproc_store:add_transition(Store, IID2, Trn23, [Msg231]),
    % Testing results
    {ok, Res7}= eproc_router:lookup(KeyAsync, RouterOpts),
    ?assertThat(lists:sort(Res7),                          is(IID12Sorted)),
    {ok, Res8}= eproc_router:lookup(KeySyncM, RouterOpts),
    ?assertThat(lists:sort(Res8),                          is(IID12Sorted)),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, [IID1]})),
    ?assertThat(eproc_router:lookup(KeySyAsy, RouterOpts), is({ok, [IID1]})),
    %
    % Check, if keys are available after instances are terminated.
    ?assertThat(eproc_store:set_instance_killed(Store, {inst, IID1}, #user_action{}), is({ok, IID1})),
    ?assertThat(eproc_store:set_instance_killed(Store, {inst, IID2}, #user_action{}), is({ok, IID2})),
    ?assertThat(eproc_router:lookup(KeyAsync, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(KeySyncM, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(KeySyncU, RouterOpts), is({ok, []})),
    ?assertThat(eproc_router:lookup(KeySyAsy, RouterOpts), is({ok, []})),
    ok.


%%
%%  Check if store operations for handling `eproc_router` attributes (keys) respect uniq option.
%%  Only sync add_router cases are tested.
%%
eproc_store_router_test_uniq(Config) ->
    ok = meck:new(eproc_fsm, [passthrough]),
    CurrentFsmFun = fun(InstId) -> meck:expect(eproc_fsm, id, [{[], {ok, InstId}}]) end,
    Store = store(Config),
    Now = os:timestamp(),
    Key1 = {eproc_store_router_test_uniq, {Now, 1}},
    Key2 = {eproc_store_router_test_uniq, {Now, 2}},
    RouterOpts = [{store, Store}],
    %%
    %%  Add instances.
    %%
    {ok, IID1} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID2} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID3} = eproc_store:add_instance(Store, inst_value()),
    SortedIds12 = lists:sort([IID1, IID2]),
    ok = CurrentFsmFun(IID1),
    ok = eproc_router:add_key(Key1, '_', [sync]),                           % Adding non unique key to inst 1
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, [IID1]})),
    ok = eproc_router:add_key(Key1, '_', [sync]),                           % Adding non unique key to inst 1 repeatedly
    ?assertThat(eproc_router:lookup(Key1, RouterOpts), is({ok, [IID1]})),
    ok = CurrentFsmFun(IID2),
    ok = eproc_router:add_key(Key1, '_', [sync]),                           % Adding non unique key to inst 2
    {ok, LookupIds1} = eproc_router:lookup(Key1, RouterOpts),
    ?assertThat(lists:sort(LookupIds1), is(SortedIds12)),
    ok = eproc_router:add_key(Key1, '_', [sync]),                           % Adding non unique key to inst 2 repeatedly
    {ok, LookupIds2} = eproc_router:lookup(Key1, RouterOpts),
    ?assertThat(lists:sort(LookupIds2), is(SortedIds12)),
    ok = CurrentFsmFun(IID3),
    {error, exists} = eproc_router:add_key(Key1, '_', [sync, uniq]),        % Adding existing key as unique to inst 3
    {ok, LookupIds3} = eproc_router:lookup(Key1, RouterOpts),
    ?assertThat(lists:sort(LookupIds3), is(SortedIds12)),
    ok = eproc_router:add_key(Key2, '_', [sync, uniq]),                     % Adding new unique key to inst 3
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID3]})),
    ok = eproc_router:add_key(Key2, next, [sync, uniq]),                    % Adding existing unique key to the same inst 3 with updated scope
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID3]})),
    ok = CurrentFsmFun(IID2),
    {error, exists} = eproc_router:add_key(Key2, '_', [sync, uniq]),        % Adding existing key as unique to inst 2
    ?assertThat(eproc_router:lookup(Key2, RouterOpts), is({ok, [IID3]})),
    true = meck:validate([eproc_fsm]),
    ok = meck:unload([eproc_fsm]).



%% =============================================================================
%%  Testcases: Meta
%% =============================================================================

%%
%%  Check if store operations for handling `eproc_module` attributes (tags) works.
%%
eproc_store_meta_test_attrs(Config) ->
    Store = store(Config),
    Tag1 = erlang:term_to_binary(erlang:make_ref()),
    Tag2 = erlang:term_to_binary(erlang:make_ref()),
    Tag3 = erlang:term_to_binary(erlang:make_ref()),
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


%% =============================================================================
%%  Testcases: Attachments
%% =============================================================================

%%
%%  Check if attachments handling works. Only InstIds are used to identify owners.
%%
eproc_store_attachment_test_instid(Config) ->
    % Initialise
    Store = store(Config),
    {ok, IID1} = eproc_store:add_instance(Store, inst_value()),
    {ok, IID2} = eproc_store:add_instance(Store, inst_value()),
    Inst1 = {inst, IID1},
    Inst2 = {inst, IID2},
    {Key1, Value1, Value1o}  = {key1,                                value1,                   value1_other },
    {Key2, Value2}           = { key2,                               {complicated, [value], 2} },
    {Key3, Value3}           = { {[complicated, long], key, 3, res}, value3 },
    {Key4, Value4}           = { key4,                               value4 },
    % Test cases
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({error, not_found})),
    ?assertThat(eproc_store:attachment_save(Store, Key1, Value1, Inst1, [{overwrite, true}]), is(ok)),
    ?assertThat(eproc_store:attachment_save(Store, Key2, Value2, Inst2, [{overwrite, false}]), is(ok)),
    ?assertThat(eproc_store:attachment_save(Store, Key3, Value3, Inst1, []), is(ok)),
    ?assertThat(eproc_store:attachment_save(Store, Key4, Value4, undefined, []), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({ok, Value1})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({ok, Value2})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_read(Store, Key4), is({ok, Value4})),
    ?assertThat(eproc_store:attachment_delete(Store, Key1), is(ok)),
    ?assertThat(eproc_store:attachment_delete(Store, Key2), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_read(Store, Key4), is({ok, Value4})),
    ?assertThat(eproc_store:attachment_save(Store, Key1, Value1, Inst1, []), is(ok)),
    ?assertThat(eproc_store:attachment_save(Store, Key2, Value2, Inst2, []), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({ok, Value1})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({ok, Value2})),
    ?assertThat(eproc_store:attachment_save(Store, Key1, Value1o, Inst2, []), is({error, duplicate})),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({ok, Value1})),
    ?assertThat(eproc_store:attachment_save(Store, Key1, Value1o, Inst2, [{overwrite, false}]), is({error, duplicate})),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({ok, Value1})),
    ?assertThat(eproc_store:attachment_save(Store, Key1, Value1o, Inst2, [{overwrite, true}]), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({ok, Value1o})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({ok, Value2})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_read(Store, Key4), is({ok, Value4})),
    ?assertThat(eproc_store:attachment_cleanup(Store, Inst2), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_read(Store, Key4), is({ok, Value4})),
    ?assertThat(eproc_store:attachment_cleanup(Store, Inst1), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key4), is({ok, Value4})),
    ok.


%%
%%  Check if owners can be referenced by name as well as by inst id.
%%
eproc_store_attachment_test_name(Config) ->
    % Initialise
    Store = store(Config),
    Inst = inst_value(),
    Name1 = name1,
    Name2 = name2,
    Name3 = name3,
    {ok, _IID1} = eproc_store:add_instance(Store, Inst#instance{name = Name1}),
    {ok,  IID2} = eproc_store:add_instance(Store, Inst#instance{name = Name2}),
    {ok,  IID3} = eproc_store:add_instance(Store, Inst#instance{name = Name3}),
    {Key1, Value1} = {key1, value1},
    {Key2, Value2} = {key2, value2},
    {Key3, Value3} = {key3, value3},
    % Test cases
    ?assertThat(eproc_store:attachment_save(Store, Key1, Value1, {name, Name1}, []), is(ok)),
    ?assertThat(eproc_store:attachment_save(Store, Key2, Value2, {name, Name2}, []), is(ok)),
    ?assertThat(eproc_store:attachment_save(Store, Key3, Value3, {inst, IID3}, []), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({ok, Value1})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({ok, Value2})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_cleanup(Store, {name, Name1}), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({ok, Value2})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_cleanup(Store, {inst, IID2}), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key2), is({error, not_found})),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({ok, Value3})),
    ?assertThat(eproc_store:attachment_cleanup(Store, {name, Name3}), is(ok)),
    ?assertThat(eproc_store:attachment_read(Store, Key3), is({error, not_found})),
    % Bad cases
    {error, _} = eproc_store:attachment_save(Store, Key1, Value1, {name, not_existing_name}, []),
    ?assertThat(eproc_store:attachment_read(Store, Key1), is({error, not_found})),
    {error, _} = eproc_store:attachment_cleanup(Store, {name, not_existing_name}),
    ok.


