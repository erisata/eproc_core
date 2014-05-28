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
-export([start_link/1, ref/0]).
-export([
    supervisor_child_specs/1,
    get_instance/3,
    get_transition/4,
    get_message/3
]).
-export([
    add_instance/2,
    add_transition/4,
    set_instance_killed/3,
    set_instance_suspended/3,
    set_instance_resuming/4,
    set_instance_resumed/3,
    load_instance/2,
    load_running/2,
    attr_task/3
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
    ets:new(?KEY_TBL,  [set, public, named_table, {keypos, #router_key.key},     WC]),
    ets:new(?TAG_TBL,  [bag, public, named_table, {keypos, #meta_tag.tag},       WC]),
    ets:new(?CNT_TBL,  [set, public, named_table, {keypos, 1}]),
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
    InstId = ets:update_counter(?CNT_TBL, inst, 1),
    ResolvedGroup = if
        Group =:= new     -> InstId;
        is_integer(Group) -> Group
    end,
    case Name =:= undefined orelse ets:insert_new(?NAME_TBL, #inst_name{name = Name, inst_id = InstId}) of
        true ->
            true = ets:insert(?INST_TBL, Instance#instance{
                inst_id = InstId,
                name = Name,
                group = ResolvedGroup,
                transitions = undefined,
                curr_state = InitState,
                arch_state = InitState
            }),
            {ok, InstId};
        false ->
            {error, bad_name}
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
    true = is_list(AttrActions),
    [Instance = #instance{
        status = OldStatus,
        curr_state = OldCurrState
    }] = ets:lookup(?INST_TBL, InstId),
    InstWithNewState = Instance#instance{
        curr_state = eproc_store:apply_transition(Transition, OldCurrState, InstId)
    },
    Action = case eproc_store:determine_transition_action(Transition, OldStatus) of
        none              -> {ok, fun () -> true = ets:insert(?INST_TBL, InstWithNewState), ok end};
        {suspend, Reason} -> {ok, fun () -> write_instance_suspended(InstWithNewState, Reason) end};
        resume            -> {ok, fun () -> write_instance_resumed(InstWithNewState, TrnNr) end};
        terminate         -> {ok, fun () -> write_instance_terminated(InstWithNewState, Status, normal) end};
        {error, Reason}   -> {error, Reason}
    end,
    case Action of
        {ok, InstFun} ->
            ok = handle_attr_actions(InstWithNewState, Transition, Messages),
            [ true = ets:insert(?MSG_TBL, Message) || Message <- Messages],
            true = ets:insert(?TRN_TBL, Transition#transition{trn_id = {InstId, TrnNr}, interrupts = []}),
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
%%  Loads instance data for runtime.
%%
load_instance(_StoreArgs, FsmRef) ->
    read_instance(FsmRef, current).


%%
%%  Load start specs for all currently running FSMs.
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
    ResolvedFrom = case From of
        current ->
            case read_instance(FsmRef, current) of
                {ok, #instance{inst_id = IID, curr_state = #inst_state{stt_id = CurrTrnNr}}} ->
                    {ok, IID, CurrTrnNr};
                {error, ReadErr} ->
                    {error, ReadErr}
            end;
        _ when is_integer(From) ->
            case resolve_inst_id(FsmRef) of
                {ok, IID}           -> {ok, IID, From};
                {error, ResolveErr} -> {error, ResolveErr}
            end
    end,
    case ResolvedFrom of
        {ok, InstId, FromTrnNr} -> read_transitions(InstId, FromTrnNr, Count, true);
        {error, Reason}         -> {error, Reason}
    end.


%%
%%
%%
get_message(_StoreArgs, MsgId, all) ->
    {InstId, TrnNr, MsgNr} = case MsgId of
        {I, T, M}    -> {I, T, M};
        {I, T, M, _} -> {I, T, M}
    end,
    case read_message({InstId, TrnNr, MsgNr, recv}) of
        {error, not_found} ->
            case read_message({InstId, TrnNr, MsgNr, sent}) of
                {error, not_found} ->
                    {error, not_found};
                {ok, Message} ->
                    {ok, Message#message{msg_id = {I, T, M}}}
            end;
        {ok, Message} ->
            {ok, Message#message{msg_id = {I, T, M}}}
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
%%  Read single message by message copy id.
%%
read_message(MsgCid) ->
    case ets:lookup(?MSG_TBL, MsgCid) of
        []        -> {error, not_found};
        [Message] -> {ok, Message}
    end.


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
    end.


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
        {create, _Name, _Scope, {data, Key, _SyncRef}} ->
            true = ets:insert(?KEY_TBL, #router_key{key = Key, inst_id = InstId, attr_nr = AttrNr}),
            ok;
        {remove, _Reason} ->
            true = ets:match_delete(?KEY_TBL, #router_key{inst_id = InstId, attr_nr = AttrNr, _ = '_'}),
            ok
    end.

%%
%%
%%
handle_attr_custom_router_task({key_sync, Key, InstId, Uniq}) ->
    AddKeyFun = fun () ->
        SyncRef = {'eproc_router$key_sync', node(), erlang:now()},
        true = ets:insert_new(?KEY_TBL, #router_key{key = Key, inst_id = InstId, attr_nr = SyncRef}),
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
        all_lists_contain(IID, OtherSets)
    end,
    Intersection = lists:filter(IntersectionFun, lists:usort(FirstSet)),
    {ok, Intersection}.



%% =============================================================================
%%  Helper functions.
%% =============================================================================

%%
%%  Checks, if all lists contain the specified element.
%%
all_lists_contain(_Element, []) ->
    true;

all_lists_contain(Element, [List | Other]) ->
    case lists:member(Element, List) of
        false -> false;
        true -> all_lists_contain(Element, Other)
    end.


