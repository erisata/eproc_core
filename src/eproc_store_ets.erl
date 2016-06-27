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
%%  ETS-based EProc store implementation.
%%  Mainly created to simplify management of unit and integration tests.
%%  Its also a Reference implementation for the store.
%%
%%  TODO: Add support for "no_history" mode.
%%
-module(eproc_store_ets).
-behaviour(eproc_store).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1, ref/0, truncate/0]).
-export([
    supervisor_child_specs/1,
    get_instance/3,
    get_transition/4,
    get_state/4,
    get_message/3,
    get_node/1
]).
-export([
    add_instance/2,
    add_transition/4,
    set_instance_killed/3,
    set_instance_suspended/3,
    set_instance_resuming/4,
    set_instance_resumed/3,
    add_inst_crash/6,
    load_instance/2,
    load_running/2,
    attr_task/3
]).
-export([
    attachment_save/5,
    attachment_read/2,
    attachment_delete/2,
    attachment_cleanup/2
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").

-define(INST_TBL, 'eproc_store_ets$instance').
-define(NAME_TBL, 'eproc_store_ets$inst_name').
-define(TRN_TBL,  'eproc_store_ets$transition').
-define(MSG_TBL,  'eproc_store_ets$message').
-define(KEY_TBL,  'eproc_store_ets$router_key').
-define(TAG_TBL,  'eproc_store_ets$meta_tag').
-define(CNT_TBL,  'eproc_store_ets$counter').
-define(ATT_TBL,  'eproc_store_ets$attachment').
-define(ATI_TBL,  'eproc_store_ets$att_inst').

-define(NODE_REF, main).

-record(inst_name, {
    name    :: inst_name(),
    inst_id :: inst_id()
}).

-record(router_key, {
    key     :: term(),
    inst_id :: inst_id(),
    attr_nr :: attr_nr()
}).

-record(meta_tag, {
    tag     :: binary(),
    type    :: binary(),
    inst_id :: inst_id(),
    attr_nr :: attr_nr()
}).



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Starts this store implementation.
%%
start_link(Name) ->
    gen_server:start_link(Name, ?MODULE, {}, []).


%%
%%  Create reference to this store.
%%
ref() ->
    eproc_store:ref(?MODULE, {}).


%%
%%  Truncate all the tables of the EProc ETS store.
%%  This function can be usefull when writing integration
%%  tests, to prepare clean environment for each test case.
%%
%%  Counters are left unchanged.
%%
truncate() ->
    true = ets:delete_all_objects(?INST_TBL),
    true = ets:delete_all_objects(?NAME_TBL),
    true = ets:delete_all_objects(?TRN_TBL),
    true = ets:delete_all_objects(?MSG_TBL),
    true = ets:delete_all_objects(?KEY_TBL),
    true = ets:delete_all_objects(?TAG_TBL),
    true = ets:delete_all_objects(?ATT_TBL),
    true = ets:delete_all_objects(?ATI_TBL),
    ok.


%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  Creates ETS tables.
%%
init({}) ->
    WC = {write_concurrency, true},
    ets:new(?INST_TBL, [set, public, named_table, {keypos, #instance.inst_id},   WC]),
    ets:new(?NAME_TBL, [set, public, named_table, {keypos, #inst_name.name},     WC]),
    ets:new(?TRN_TBL,  [set, public, named_table, {keypos, #transition.trn_id},  WC]),
    ets:new(?MSG_TBL,  [set, public, named_table, {keypos, #message.msg_id},     WC]),
    ets:new(?KEY_TBL,  [bag, public, named_table, {keypos, #router_key.key},     WC]),
    ets:new(?TAG_TBL,  [bag, public, named_table, {keypos, #meta_tag.tag},       WC]),
    ets:new(?CNT_TBL,  [set, public, named_table, {keypos, 1}]),
    ets:new(?ATT_TBL,  [set, public, named_table, {keypos, 1},                   WC]),
    ets:new(?ATI_TBL,  [bag, public, named_table, {keypos, 1},                   WC]),
    ets:insert(?CNT_TBL, {inst, 0}),
    State = undefined,
    {ok, State}.


%%
%%  Unused.
%%
handle_call(_Event, _From, State) ->
    {reply, ok, State}.


%%
%%  Unused.
%%
handle_cast(_Event, State) ->
    {noreply, State}.


%%
%%  Unused.
%%
handle_info(_Event, State) ->
    {noreply, State}.


%%
%%  Deletes ETS tables.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Used for hot-upgrades.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Callbacks for `eproc_store`.
%% =============================================================================

%%
%%  Returns supervisor child specifications for starting the store.
%%
supervisor_child_specs(_StoreArgs) ->
    Mod = ?MODULE,
    Spec = {Mod, {Mod, start_link, [{local, Mod}]}, permanent, 10000, worker, [Mod]},
    {ok, [Spec]}.


%%
%%  Add new instance to the store.
%%
add_instance(_StoreArgs, Instance = #instance{name = Name, group = Group, curr_state = InitState})->
    InstId = {ets:update_counter(?CNT_TBL, inst, 1), ?NODE_REF},
    ResolvedGroup = if
        Group =:= new -> InstId;
        true          -> Group
    end,
    case Name =:= undefined orelse ets:insert_new(?NAME_TBL, #inst_name{name = Name, inst_id = InstId}) of
        true ->
            true = ets:insert(?INST_TBL, Instance#instance{
                inst_id = InstId,
                name = Name,
                group = ResolvedGroup,
                create_node = ?NODE_REF,
                transitions = undefined,
                curr_state = InitState,
                arch_state = InitState
            }),
            {ok, InstId};
        false ->
            case resolve_inst_id({name, Name}) of
                {ok, OldInstId} -> {error, {already_created, OldInstId}};
                {error, Reason} -> {error, Reason}
            end
    end.


%%
%%  Add a transition for an existing instance.
%%
add_transition(_StoreArgs, InstId, Transition, Messages) ->
    #transition{
        trn_id       = TrnNr,
        attr_actions = AttrActions,
        inst_status  = Status
    } = Transition,
    NormalizedTransition = Transition#transition{
        trn_node = ?NODE_REF
    },
    true = is_list(AttrActions),
    [Instance = #instance{
        status = OldStatus,
        curr_state = OldCurrState
    }] = ets:lookup(?INST_TBL, InstId),
    InstWithNewState = Instance#instance{
        curr_state = eproc_store:apply_transition(NormalizedTransition, OldCurrState, InstId)
    },
    Action = case eproc_store:determine_transition_action(NormalizedTransition, OldStatus) of
        none              -> {ok, fun () -> true = ets:insert(?INST_TBL, InstWithNewState), ok end};
        {suspend, Reason} -> {ok, fun () -> write_instance_suspended(InstWithNewState, Reason) end};
        resume            -> {ok, fun () -> write_instance_resumed(InstWithNewState, TrnNr) end};
        terminate         -> {ok, fun () -> write_instance_terminated(InstWithNewState, Status, normal) end};
        {error, Reason}   -> {error, Reason}
    end,
    case Action of
        {ok, InstFun} ->
            ok = handle_attr_actions(InstWithNewState, NormalizedTransition, Messages),
            [ true = ets:insert(?MSG_TBL, Message) || Message <- Messages],
            true = ets:insert(?TRN_TBL, NormalizedTransition#transition{
                trn_id = {InstId, TrnNr},
                interrupts = []
            }),
            ok = InstFun(),
            {ok, InstId, TrnNr};
        {error, ErrReason} ->
            {error, ErrReason}
    end.


%%
%%  Mark instance as killed.
%%
set_instance_killed(_StoreArgs, FsmRef, UserAction) ->
    case read_instance(FsmRef, full) of
        {error, Reason} ->
            {error, Reason};
        {ok, Instance = #instance{inst_id = InstId, status = Status}} ->
            case eproc_store:is_instance_terminated(Status) of
                false ->
                    ok = write_instance_terminated(Instance, killed, UserAction),
                    {ok, InstId};
                true ->
                    {ok, InstId}
            end
    end.


%%
%%  Mark instance as suspended.
%%
set_instance_suspended(_StoreArgs, FsmRef, Reason) ->
    case read_instance(FsmRef, full) of
        {error, FailReason} ->
            {error, FailReason};
        {ok, Instance = #instance{inst_id = InstId, status = Status}} ->
            case {eproc_store:is_instance_terminated(Status), Status} of
                {true, _} ->
                    {error, terminated};
                {false, suspended} ->
                    {ok, InstId};
                {false, resuming} ->
                    ok = write_instance_suspended(Instance, Reason),
                    {ok, InstId};
                {false, running} ->
                    ok = write_instance_suspended(Instance, Reason),
                    {ok, InstId}
            end
    end.


%%
%%  Mark instance as resuming after it was suspended.
%%
set_instance_resuming(_StoreArgs, FsmRef, StateAction, UserAction) ->
    case read_instance(FsmRef, full) of
        {error, FailReason} ->
            {error, FailReason};
        {ok, Instance = #instance{inst_id = InstId, status = Status, start_spec = StartSpec}} ->
            case {eproc_store:is_instance_terminated(Status), Status} of
                {true, _} ->
                    {error, terminated};
                {false, running} ->
                    {error, running};
                {false, Status} when Status =:= suspended; Status =:= resuming ->
                    case write_instance_resuming(Instance, StateAction, UserAction) of
                        ok                  -> {ok, InstId, StartSpec};
                        {error, FailReason} -> {error, FailReason}
                    end
            end
    end.


%%
%%  Mark instance as successfully resumed.
%%
set_instance_resumed(_StoreArgs, InstId, TrnNr) ->
    case read_instance({inst, InstId}, full) of
        {error, FailReason} ->
            {error, FailReason};
        {ok, Instance} ->
            case write_instance_resumed(Instance, TrnNr) of
                ok -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.


%%
%%  Register a crash, occured with the specified instance.
%%
add_inst_crash(_StoreArgs, _InstId, _LastTrnNr, _Pid, _Msg, _Reason) ->
    % TODO: Implement it.
    ok.


%%
%%  Loads instance data for runtime.
%%
load_instance(_StoreArgs, FsmRef) ->
    read_instance(FsmRef, current).


%%
%%  Load start specs for all currently running FSMs.
%%
%%  NOTE: The `resuming` state is not included here intentionally.
%%  The process stuck in the `resuming` state can be resumed again
%%  by calling `eproc_fsm:resume/2` explicitly. It was considered
%%  to be better to leave the resume attemts maintained manually.
%%
load_running(_StoreArgs, PartitionPred) ->
    FilterFun = fun
        (#instance{inst_id = InstId, group = Group, start_spec = StartSpec, status = running}, Filtered) ->
            case PartitionPred(InstId, Group) of
                true  ->
                    [{{inst, InstId}, StartSpec} | Filtered];
                false ->
                    Filtered
            end;
        (_Other, Filtered) ->
            Filtered
    end,
    Running = ets:foldl(FilterFun, [], ?INST_TBL),
    {ok, Running}.


%%
%%  Handle attribute tasks.
%%
attr_task(_StoreArgs, AttrModule, AttrTask) ->
    case AttrModule of
        eproc_router -> handle_attr_custom_router_task(AttrTask);
        eproc_meta   -> handle_attr_custom_meta_task(AttrTask)
    end.


%%
%%  Get instance data.
%%
get_instance(StoreArgs, {filter, {ResFrom, ResCount}, Filters}, Query) ->
    get_instance(StoreArgs, {filter, {ResFrom, ResCount, last_trn}, Filters}, Query);

get_instance(_StoreArgs, {filter, {ResFrom, ResCount, SortedBy}, Filters}, Query) ->
    {ok, MatchSpec} = eproc_store:instance_filter_to_ms(Filters, [tag]),
    {ok, Grouped, _Other} = eproc_store:group_filter_by_type(Filters, [id, tag]),
    [IdClauses, TagClauses] = Grouped,
    FilterFuns = [
        fun (Insts) -> resolve_instance_id_filter  (Insts, IdClauses           ) end,
        % Names cannot be resolved as prefilters, because terminated instances are not present in ?INST_TBL
        fun (Insts) -> resolve_instance_tag_filters(Insts, TagClauses          ) end,
        fun (Insts) -> resolve_match_filter        (Insts, ?INST_TBL, MatchSpec) end
    ],
    FilterApplyFun = fun
        (_Fun, [])    -> [];
        (Fun,  Insts) -> Fun(Insts)
    end,
    InstancesPreSort = lists:foldl(FilterApplyFun, undefined, FilterFuns),
    InstancesSortedPreQ = eproc_store:instance_sort(InstancesPreSort, SortedBy),
    ReadInstDataFun = fun (InstancePreQ) ->
        {ok, InstanceRez} = read_instance_data(InstancePreQ, Query),
        InstanceRez
    end,
    Instances = lists:map(ReadInstDataFun, InstancesSortedPreQ),
    {ok, {erlang:length(Instances), true, eproc_store:sublist_opt(Instances, ResFrom, ResCount)}};

get_instance(_StoreArgs, {list, FsmRefs}, Query) when is_list(FsmRefs) ->
    ReadFun = fun
        (FsmRef, {ok, Insts}) ->
            case read_instance(FsmRef, Query) of
                {ok, Inst}      -> {ok, [Inst | Insts]};
                {error, Reason} -> {error, Reason}
            end;
        (_FsmRef, {error, Reason}) ->
            {error, Reason}
    end,
    case lists:foldl(ReadFun, {ok, []}, FsmRefs) of
        {ok, Instances} -> {ok, lists:reverse(Instances)};
        {error, Reason} -> {error, Reason}
    end;

get_instance(_StoreArgs, FsmRef, Query) ->
    read_instance(FsmRef, Query).


%%
%%
%%
get_transition(_StoreArgs, FsmRef, TrnNr, all) when is_integer(TrnNr) ->
    case resolve_inst_id(FsmRef) of
        {ok, InstId}    -> read_transition(InstId, TrnNr, true);
        {error, Reason} -> {error, Reason}
    end;

get_transition(_StoreArgs, FsmRef, {list, From, Count}, all) ->
    case read_instance(FsmRef, current) of
        {ok, #instance{inst_id = IID, curr_state = #inst_state{stt_id = CurrTrnNr}}} ->
            RealFrom = case From of
                current                            -> CurrTrnNr;
                _ when is_integer(From), From > 0  -> From;
                _ when is_integer(From), From =< 0 -> CurrTrnNr+From
            end,
            case read_transitions(IID, RealFrom, Count, true) of
                {ok, TrnList}       -> {ok, {CurrTrnNr, true, TrnList}};
                {error, ReadTrnErr} -> {error, ReadTrnErr}
            end;
        {error, ReadInstErr} ->
            {error, ReadInstErr}
    end.


%%
%%
%%
get_state(StoreArgs, FsmRef, SttNr, all) when is_integer(SttNr); SttNr =:= current ->
    case get_state(StoreArgs, FsmRef, {list, SttNr, 1}, all) of
        {ok, [InstState]} -> {ok, InstState};
        {error, Reason}   -> {error, Reason}
    end;

get_state(_StoreArgs, FsmRef, {list, From, Count}, all) ->
    case read_instance(FsmRef, full) of
        {ok, Instance} ->
            #instance{
                inst_id = IID,
                curr_state = #inst_state{stt_id = CurrSttNr},
                arch_state = #inst_state{stt_id = ArchSttNr} = ArchState
            } = Instance,
            FromSttNr = case From of
                current -> CurrSttNr;
                _       -> From
            end,
            case FromSttNr =< CurrSttNr of
                true ->
                    TillSttNr = erlang:max(ArchSttNr, FromSttNr - Count + 1),
                    {_, InstStates} = lists:foldl(
                        fun (SttNr, {PrevState, States}) ->
                            State = derive_state(IID, SttNr, PrevState),
                            {State, [State | States]}
                        end,
                        {ArchState, []},
                        lists:seq(TillSttNr, FromSttNr)
                    ),
                    {ok, InstStates};
                false ->
                    lager:error("Non-existing state requested, from=~p, current=~p", [FromSttNr, CurrSttNr]),
                    {error, not_found}
            end;
        {error, ReadErr} ->
            {error, ReadErr}
    end.


%%
%%
%%
get_message(StoreArgs, {filter, {ResFrom, ResCount}, Filters}, Query) ->
    get_message(StoreArgs, {filter, {ResFrom, ResCount, date}, Filters}, Query);

get_message(_StoreArgs, {filter, {ResFrom, ResCount, SortedBy}, Filters}, _Query) ->
    {ok, MatchSpec} = eproc_store:message_filter_to_ms(Filters, []),
    {ok, [IdFilters], _Others} = eproc_store:group_filter_by_type(Filters, [id]),
    FilterFuns = [
        fun (Messages) -> resolve_message_id_filter   (Messages, IdFilters) end,
        fun (Messages) -> resolve_message_match_filter(Messages, MatchSpec) end
    ],
    FilterApplyFun = fun
        (_Fun, [])    -> [];
        (Fun,  Insts) -> Fun(Insts)
    end,
    MessagesFiltered = lists:foldl(FilterApplyFun, undefined, FilterFuns),
    MessagesPreSort = lists:map(fun eproc_store:normalise_message/1, MessagesFiltered),
    MessagesSorted = eproc_store:message_sort(MessagesPreSort, SortedBy),
    {ok, {erlang:length(MessagesSorted), true, eproc_store:sublist_opt(MessagesSorted, ResFrom, ResCount)}};

get_message(_StoreArgs, {list, MsgIds}, _Query) ->
    ReadFun = fun
        (MsgId, {ok, Messages}) ->
            case read_message_normalised(MsgId) of
                {ok, Message}   -> {ok, [Message | Messages]};
                {error, Reason} -> {error, Reason}
            end;
        (_MsgId, {error, Reason}) ->
            {error, Reason}
    end,
    case lists:foldl(ReadFun, {ok, []}, MsgIds) of
        {ok, Messages}  -> {ok, lists:reverse(Messages)};
        {error, Reason} -> {error, Reason}
    end;

get_message(_StoreArgs, MsgId, _Query) ->
    read_message_normalised(MsgId).


%%
%%
%%
get_node(_StoreArgs) ->
    {ok, ?NODE_REF}.


%%
%%
%%
attachment_save(_StoreArgs, Key, Value, Owner, Opts) ->
    Overwrite = proplists:get_value(overwrite, Opts, false),
    OwnerResolved = case Owner of
        undefined -> {ok, undefined};
        _         -> resolve_inst_id(Owner)
    end,
    InsertOwnerKeyFun = fun
        (undefined, _K) -> true;
        (OwnerIID,   K) -> ets:insert(?ATI_TBL, {OwnerIID, K})
    end,
    case {OwnerResolved, Overwrite} of
        {{ok, OwnerId}, true} ->
            true = case ets:lookup(?ATT_TBL, Key) of
                []                            -> true;
                [{Key, _OldValue, undefined}] -> true;
                [{Key, _OldValue, OldOwner}]  -> ets:delete_object(?ATI_TBL, {OldOwner, Key})
            end,
            true = ets:insert(?ATT_TBL, {Key, Value, OwnerId}),
            true = InsertOwnerKeyFun(OwnerId, Key),
            ok;
        {{ok, OwnerId}, false} ->
            case ets:insert_new(?ATT_TBL, {Key, Value, OwnerId}) of
                true ->
                    true = InsertOwnerKeyFun(OwnerId, Key),
                    ok;
                false ->
                    {error, duplicate}
            end;
        {{error, Reason}, _} ->
            {error, Reason}
    end.


%%
%%
%%
attachment_read(_StoreArgs, Key) ->
    case ets:lookup(?ATT_TBL, Key) of
        []                     -> {error, not_found};
        [{Key, Value, _Owner}] -> {ok, Value}
    end.


%%
%%
%%
attachment_delete(_StoreArgs, Key) ->
    case ets:lookup(?ATT_TBL, Key) of
        [] ->
            ok;
        [{Key, _Value, undefined}] ->
            true = ets:delete(?ATT_TBL, Key),
            ok;
        [{Key, _Value, Owner}] ->
            true = ets:delete_object(?ATI_TBL, {Owner, Key}),
            true = ets:delete(?ATT_TBL, Key),
            ok
    end.


%%
%%
%%
attachment_cleanup(_StoreArgs, Owner) ->
    case resolve_inst_id(Owner) of
        {ok, OwnerId} ->
            Objects = ets:take(?ATI_TBL, OwnerId),
            lists:foreach(fun({_, Key}) ->
                true = ets:delete(?ATT_TBL, Key)
            end, Objects),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolve Instance Id from FSM Reference.
%%
resolve_inst_id({inst, InstId}) ->
    {ok, InstId};

resolve_inst_id({name, Name}) ->
    case ets:lookup(?NAME_TBL, Name) of
        [] ->
            {error, not_found};
        [#inst_name{inst_id = InstId}] ->
            {ok, InstId}
    end.


%%
%%  Resolve partially filled msg reference, if possible.
%%
resolve_msg_ref(MsgRef = #msg_ref{cid = {I, T, M, sent}, peer = {inst, undefined}}) ->
    case read_message({I, T, M, recv}) of
        {ok, #message{receiver = NewPeer}} ->
            MsgRef#msg_ref{peer = NewPeer};
        {error, not_found} ->
            MsgRef
    end;

resolve_msg_ref(MsgRef) ->
    MsgRef.


%%
%%  Resolve partially filled message, if possible.
%%
resolve_message(Message = #message{msg_id = {I, T, M, sent}, receiver = {inst, undefined}}) ->
    case read_message({I, T, M, recv}) of
        {ok, #message{receiver = NewReceiver}} ->
            Message#message{receiver = NewReceiver};
        {error, not_found} ->
            Message
    end;

resolve_message(Message) ->
    Message.


%%
%%  Reads instance record.
%%
read_instance(FsmRef, Query) ->
    case resolve_inst_id(FsmRef) of
        {ok, InstId} ->
            case ets:lookup(?INST_TBL, InstId) of
                [] ->
                    {error, not_found};
                [Instance] ->
                    read_instance_data(Instance, Query)
            end;
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Reads a list of instances ignoring all the errors.
%%
read_instance_list_opt(Type, Keys) ->
    ReadInstFun = fun (FsmRef) ->
        case resolve_inst_id(FsmRef) of
            {ok, InstId} ->
                ets:lookup(?INST_TBL, InstId);
            {error, _Reason} ->
                []
        end
    end,
    lists:append(lists:map(ReadInstFun, [ {Type, Key} || Key <- Keys ])).


%%
%%  Reads instance related data according to query.
%%
read_instance_data(Instance, header) ->
    {ok, Instance#instance{curr_state = undefined, arch_state = undefined, transitions = undefined}};

read_instance_data(Instance, recent) ->
    read_instance_data(Instance, current);

read_instance_data(Instance, current) ->
    {ok, Instance#instance{arch_state = undefined, transitions = undefined}};

read_instance_data(Instance, full) ->
    {ok, Instance}.


%%
%%  Read single transition.
%%
read_transition(InstId, TrnNr, ResolveMsgRefs) ->
    case ets:lookup(?TRN_TBL, {InstId, TrnNr}) of
        [] ->
            {error, not_found};
        [Transition = #transition{trn_messages = TrnMessages}] ->
            case ResolveMsgRefs of
                true ->
                    NewTrnMessages = lists:map(fun resolve_msg_ref/1, TrnMessages),
                    {ok, Transition#transition{trn_id = TrnNr, trn_messages = NewTrnMessages}};
                false ->
                    {ok, Transition}
            end
    end.


%%
%%  Read a list of transitions.
%%
read_transitions(_InstId, From, Count, _ResolveMsgRefs) when Count =< 0; From =< 0->
    {ok, []};

read_transitions(InstId, From, Count, ResolveMsgRefs) ->
    case read_transition(InstId, From, ResolveMsgRefs) of
        {ok, Transition} ->
            case read_transitions(InstId, From - 1, Count - 1, ResolveMsgRefs) of
                {ok, Transitions} -> {ok, [Transition | Transitions]};
                {error, Reason}   -> {error, Reason}
            end;
        {error, not_found} ->
            {ok, []};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Read single message by message copy id or message id.
%%  Returns `{ok, #message{}}`, if message is found and `{error, not_found}`,
%%  if message with given ID is not found.
%%
%%  In the case of message id, received message takes priority over sent one.
%%
read_message({_InstId, _TrnNr, _MsgNr, _Copy} = MsgCid) ->
    case ets:lookup(?MSG_TBL, MsgCid) of
        []        -> {error, not_found};
        [Message] -> {ok, Message}
    end;

read_message({InstId, TrnNr, MsgNr}) ->
    case read_message({InstId, TrnNr, MsgNr, recv}) of
        {error, not_found} ->
            case read_message({InstId, TrnNr, MsgNr, sent}) of
                {error, not_found} ->
                    {error, not_found};
                {ok, Message} ->
                    {ok, Message}
            end;
        {ok, Message} ->
            {ok, Message}
    end.


%%
%% Reads a single message by message id or message copy id.
%% In #message{} record of the returned tuple message copy id is replaced by
%% message id.
%%
read_message_normalised(MsgId) ->
    case read_message(MsgId) of
        {ok, Message}   -> {ok, eproc_store:normalise_message(resolve_message(Message))};
        {error, Reason} -> {error, Reason}
    end.


%%
%% Reads a list of message by message id and ignores all the errors.
%% Returns a list of messages, which were found.
%%
read_message_list_ids(MsgIds) ->
    ReadInstFun = fun(MsgId) ->
        case read_message(MsgId) of
            {ok, Message}   -> {true, Message};
            {error, _}      -> false
        end
    end,
    lists:filtermap(ReadInstFun, MsgIds).


%%
%%  Get specified state based on a previous state
%%
derive_state(_InstId, SttNr, OlderState = #inst_state{stt_id = SttNr}) ->
    OlderState;

derive_state(InstId, SttNr, OlderState = #inst_state{stt_id = OlderSttNr}) when SttNr > OlderSttNr ->
    PrevState = derive_state(InstId, SttNr - 1, OlderState),
    {ok, Transition} = read_transition(InstId, SttNr, false),
    eproc_store:apply_transition(Transition, PrevState, InstId).


%%
%%  Mark instance as terminated.
%%
write_instance_terminated(Instance = #instance{inst_id = InstId, name = Name}, Status, Reason) ->
    NewInstance = Instance#instance{
        status      = Status,
        terminated  = os:timestamp(),
        term_reason = Reason
    },
    true = ets:insert(?INST_TBL, NewInstance),
    case Name of
        undefined ->
            ok;
        _ ->
            InstName = #inst_name{name = Name, inst_id = InstId},
            true = ets:delete_object(?NAME_TBL, InstName),
            ok
    end,
    ok = handle_attr_custom_router_terminated(InstId),
    ok = handle_attr_custom_meta_terminated(InstId),
    ok.


%%
%%  Mark instance as suspended.
%%
write_instance_suspended(Instance = #instance{interrupt = undefined}, Reason) ->
    Interrupt = #interrupt{
        intr_id     = undefined,
        status      = active,
        suspended   = os:timestamp(),
        reason      = Reason,
        resumes     = []
    },
    NewInstance = Instance#instance{
        status    = suspended,
        interrupt = Interrupt
    },
    true = ets:insert(?INST_TBL, NewInstance),
    ok;

write_instance_suspended(Instance = #instance{interrupt = #interrupt{}}, _Reason) ->
    NewInstance = Instance#instance{
        status = suspended
    },
    true = ets:insert(?INST_TBL, NewInstance),
    ok.


%%
%%  Mark instance as resuming.
%%
write_instance_resuming(#instance{inst_id = InstId, interrupt = Interrupt}, StateAction, UserAction) ->
    #interrupt{resumes = Resumes} = Interrupt,
    ResumeAttempt = eproc_store:make_resume_attempt(StateAction, UserAction, Resumes),
    NewInterrupt = Interrupt#interrupt{
        resumes = [ResumeAttempt | Resumes]
    },
    true = ets:update_element(?INST_TBL, InstId, [
        {#instance.status, resuming},
        {#instance.interrupt, NewInterrupt}
    ]),
    ok.


%%
%%  Mark instance as running (resumed).
%%
write_instance_resumed(Instance = #instance{interrupt = undefined}, _TrnNr) ->
    true = ets:insert(?INST_TBL, Instance),
    ok;

write_instance_resumed(Instance, TrnNr) ->
    #instance{
        inst_id = InstId,
        interrupt = Interrupt,
        curr_state = CurrState,
        arch_state = ArchState
    } = Instance,
    #inst_state{
        stt_id = CurrStateNr,
        interrupts = CurrInterrupts
    } = CurrState,
    #inst_state{
        stt_id = ArchStateNr,
        interrupts = ArchInterrupts
    } = ArchState,
    IntrNr = case CurrInterrupts of
        [                                    ] -> 1;
        [#interrupt{intr_id = LastIntrNr} | _] -> LastIntrNr + 1
    end,
    NewInterrupt = Interrupt#interrupt{
        intr_id = IntrNr,
        status = closed
    },
    NewInstance = case TrnNr of
        ArchStateNr ->
            NewArchState = ArchState#inst_state{
                interrupts = [NewInterrupt | ArchInterrupts]
            },
            Instance#instance{
                status     = running,
                interrupt  = undefined,
                arch_state = NewArchState
            };
        CurrStateNr ->
            TrnId = {InstId, TrnNr},
            true = ets:update_element(?TRN_TBL, TrnId,
                {#transition.interrupts, [NewInterrupt | CurrInterrupts]}
            ),
            Instance#instance{
                status     = running,
                interrupt  = undefined
            }
    end,
    true = ets:insert(?INST_TBL, NewInstance),
    ok.


%%
%%  Handle all attribute actions.
%%
handle_attr_actions(Instance, Transition = #transition{attr_actions = AttrActions}, Messages) ->
    Fun = fun
        (A = #attr_action{module = eproc_router}, I, _T, _M) -> handle_attr_custom_router_action(A, I);
        (A = #attr_action{module = eproc_meta},   I, _T, _M) -> handle_attr_custom_meta_action(A, I)
    end,
    [
        ok = Fun(A, Instance, Transition, Messages)
        || A = #attr_action{needs_store = true} <- AttrActions
    ],
    ok.


%%
%%  Resolves match filters. Takes name of ets table (`Table`) and match
%%  specification (`MatchSpec`) as parameter. If first parameter is undefined,
%%  queries the specified table. Otherwise, filters the list passed as a first
%%  parameter with provided match specification.
%%  Never returns undefined.
%%
resolve_match_filter(undefined, Table, MatchSpec) ->
    ets:select(Table, MatchSpec);

resolve_match_filter(Objects, _Table, MatchSpec) ->
    ets:match_spec_run(Objects, ets:match_spec_compile(MatchSpec)).


%% =============================================================================
%%  Instance filtering functions, used in `get_instance/3`.
%%  All these functions take a list of instances or undefined as the
%%  first parameter. The functions performs filtering, if the list is
%%  passed to it, and performs query, if instance list is undefined.
%%
%%  Second parameter is a list of filter clauses of the corresponding type.
%% =============================================================================

%%
%%  Resolves instance id filter. At most one such filter is expected,
%%  although several instance IDs can be provided in it. The function
%%  takes undefined, returns undefined or a list of instances. Instance
%%  filtering is not performed here and should be handled in the match
%%  spec filtering.
%%
resolve_instance_id_filter(Instances, []) ->
    Instances;

resolve_instance_id_filter(undefined, FilterClauses) ->
    InstIds = eproc_store:intersect_filter_values(FilterClauses),
    read_instance_list_opt(inst, InstIds);

resolve_instance_id_filter(Instances, _FilterClauses) ->
    Instances.  % Leave filtering for match_spec.


%%
%%  Resolves tags filters.
%%  Takes undefined or a list of instances.
%%
resolve_instance_tag_filters(Instances, []) ->
    Instances;

resolve_instance_tag_filters(undefined, FilterClauses) ->
    InstIds = resolve_instance_tag_to_inst_ids(FilterClauses),
    read_instance_list_opt(inst, InstIds);

resolve_instance_tag_filters(Instances, FilterClauses) ->
    InstIds = resolve_instance_tag_to_inst_ids(FilterClauses),
    FilterByInstId = fun (#instance{inst_id = InstId}) ->
        lists:member(InstId, InstIds)
    end,
    lists:filter(FilterByInstId, Instances).


%%
%%  Helper function for `resolve_instance_tag_filters/2`.
%%
resolve_instance_tag_to_inst_ids(FilterClauses) ->
    GetInstIdsByTagFun = fun(Tag) ->
        {TagName, TagType} = case Tag of
            {TN, TT}-> {TN, TT};
            TN      -> {TN, undefined}
        end,
        Matched = case TagType of
            undefined ->
                ets:match(?TAG_TBL, #meta_tag{tag = TagName,                 inst_id = '$1', _ = '_'});
            _ ->
                ets:match(?TAG_TBL, #meta_tag{tag = TagName, type = TagType, inst_id = '$1', _ = '_'})
        end,
        [ IID || [IID] <- Matched ]
    end,
    GetInstIdsByClauseFun = fun ({tag, TagOrList}) ->
        InstIdLists = lists:map(GetInstIdsByTagFun, eproc_store:make_list(TagOrList)),
        lists:usort(lists:append(InstIdLists))
    end,
    eproc_store:intersect_lists(lists:map(GetInstIdsByClauseFun, FilterClauses)).


%% =============================================================================
%%  Message filtering functions, used in `get_message/3`.
%%  All these functions take a list of messages or undefined as the
%%  first parameter. The functions performs filtering, if the list is
%%  passed to it, and performs query, if message list is undefined.
%%
%%  Second parameter is a list of filter clauses of the corresponding type.
%% =============================================================================

%%
%%  Resolves message id filter. At most one such filter is expected,
%%  although several message IDs can be provided in it. The function
%%  takes undefined, returns undefined or a list of messages. Message
%%  filtering is not performed here and should be handled in the match
%%  spec filtering.
%%
resolve_message_id_filter(Messages, []) ->
    Messages;

resolve_message_id_filter(undefined, FilterClauses) ->
    NormalisedFilterClauses = lists:map(fun eproc_store:normalise_message_id_filter/1, FilterClauses),
    MsgIds = eproc_store:intersect_filter_values(NormalisedFilterClauses),
    read_message_list_ids(MsgIds);

resolve_message_id_filter(Messages, _FilterClauses) ->
    Messages.  % Leave filtering for match_spec.


%%
%%  Resolves message match filters.
%%  Additionally removes equivalent messages from the returned list, if needed.
%%  Equivalent are messages with following copy ids: {I, T, M, sent} and {I, T, M, recv}.
%%  In case of collision, received message is kept.
%%
resolve_message_match_filter(Messages, MatchSpec) ->
    MessagesFiltered = resolve_match_filter(Messages, ?MSG_TBL, MatchSpec),
    case Messages of
        undefined ->
            % TODO: may be it would be better to add comparator fun to usort,
            %       which would tell that {I,T,M,sent} and {I,T,M,recv} messages are equal,
            %       even though not every case will filtered by such comparison?
            case lists:usort(MessagesFiltered) of
                [] ->
                    [];
                [MessageFirst | MessagesOther] ->
                    RemoveDuplicatesFun = fun
                        (#message{msg_id = {I, T, M, sent}}, {Message2 = #message{msg_id = {I, T, M, recv}}, MessagesCollected}) ->
                            {Message2, MessagesCollected};
                        (Message1, {Message2, MessagesCollected}) ->
                            {Message1, [Message2 | MessagesCollected]}
                    end,
                    {MessageLast, MessageList} = lists:foldl(RemoveDuplicatesFun, {MessageFirst, []}, MessagesOther),
                    [MessageLast | MessageList]
            end;
        _ ->
            MessagesFiltered
    end.


%% =============================================================================
%%  Specific attribute support: eproc_router
%% =============================================================================

%%
%%  Creates or removes router keys.
%%
%%  The sync record will be replaced, if created previously, alrough
%%  the SyncRef is not checked to keep this action atomic.
%%
handle_attr_custom_router_action(AttrAction, Instance) ->
    #attr_action{attr_nr = AttrNr, action = Action} = AttrAction,
    #instance{inst_id = InstId} = Instance,
    case Action of
        {create, _Name, _Scope, {data, Key, SyncRef}} ->
            case SyncRef of
                undefined ->
                    true;
                _ ->
                    DeletePattern = #router_key{key = Key, inst_id = InstId, attr_nr = SyncRef, _ = '_'},
                    true = ets:match_delete(?KEY_TBL, DeletePattern)
            end,
            true = ets:insert(?KEY_TBL, #router_key{key = Key, inst_id = InstId, attr_nr = AttrNr}),
            ok;
        {remove, _Reason} ->
            true = ets:match_delete(?KEY_TBL, #router_key{inst_id = InstId, attr_nr = AttrNr, _ = '_'}),
            ok
    end.

%%
%%  This is called from the process callback to add a key synchronously.
%%
handle_attr_custom_router_task({key_sync, Key, InstId, Uniq}) ->
    AddKeyFun = fun () ->
        SyncRef = {'eproc_router$key_sync', erlang:make_ref()},
        true = ets:insert(?KEY_TBL, #router_key{key = Key, inst_id = InstId, attr_nr = SyncRef}),
        {ok, SyncRef}
    end,
    case {ets:lookup(?KEY_TBL, Key), Uniq} of
        {[], _    } -> AddKeyFun();
        {_,  false} -> AddKeyFun();
        {_,  true } -> {error, exists}
    end;

handle_attr_custom_router_task({lookup, Key}) ->
    InstIds = [ InstId || #router_key{inst_id = InstId} <- ets:lookup(?KEY_TBL, Key) ],
    {ok, InstIds}.


%%
%%
%%
handle_attr_custom_router_terminated(InstId) ->
    true = ets:match_delete(?KEY_TBL, #router_key{inst_id = InstId, _ = '_'}),
    ok.



%% =============================================================================
%%  Specific attribute support: eproc_meta
%% =============================================================================

%%
%%
%%
handle_attr_custom_meta_action(AttrAction, Instance) ->
    #attr_action{attr_nr = AttrNr, action = Action} = AttrAction,
    #instance{inst_id = InstId} = Instance,
    case Action of
        {create, _Name, _Scope, {data, Tag, Type}} ->
            true = ets:insert(?TAG_TBL, #meta_tag{tag = Tag, type = Type, inst_id = InstId, attr_nr = AttrNr}),
            ok;
        {update, _NewScope, {data, _Tag, _Type}} ->
            ok;
        {remove, _Reason} ->
            ok
    end.


%%
%%
%%
handle_attr_custom_meta_task({get_instances, {tags, []}}) ->
    {ok, []};

handle_attr_custom_meta_task({get_instances, {tags, Tags}}) ->
    QueryByTagFun = fun
        ({Tag, undefined}) ->
            [IID || #meta_tag{inst_id = IID} <- ets:lookup(?TAG_TBL, Tag)];
        ({Tag, Type}) ->
            Pattern = #meta_tag{tag = Tag, type = Type, _ = '_'},
            [IID || #meta_tag{inst_id = IID} <- ets:match_object(?TAG_TBL, Pattern)]
    end,
    [FirstSet | OtherSets] = lists:map(QueryByTagFun, Tags),
    IntersectionFun = fun (IID) ->
        eproc_store:member_in_all(IID, OtherSets)
    end,
    Intersection = lists:filter(IntersectionFun, lists:usort(FirstSet)),
    {ok, Intersection}.


%%
%%
%%
handle_attr_custom_meta_terminated(_InstId) ->
    ok.



%% =============================================================================
%%  Helper functions.
%% =============================================================================



