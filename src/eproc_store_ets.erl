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
-module(eproc_store_ets).
-behaviour(eproc_store).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1]).
-export([
    supervisor_child_specs/1,
    get_instance/3,
    get_transition/4,
    get_message/3
]).
-export([
    add_instance/2,
    add_transition/3,
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
-define(INTR_TBL, 'eproc_store_ets$interrupt').
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
    attr_id :: integer()
}).

-record(meta_tag, {
    tag     :: binary(),
    type    :: binary(),
    inst_id :: inst_id(),
    attr_id :: integer()
}).



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
start_link(Name) ->
    gen_server:start_link(Name, ?MODULE, {}, []).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  Creates ETS tables.
%%
init({}) ->
    WC = {write_concurrency, true},
    ets:new(?INST_TBL, [set, public, named_table, {keypos, #instance.id},        WC]),
    ets:new(?NAME_TBL, [set, public, named_table, {keypos, #inst_name.name},     WC]),
    ets:new(?INTR_TBL, [bag, public, named_table, {keypos, #interrupt.inst_id},  WC]),
    ets:new(?TRN_TBL,  [bag, public, named_table, {keypos, #transition.inst_id}, WC]),
    ets:new(?MSG_TBL,  [set, public, named_table, {keypos, #message.id},         WC]),
    ets:new(?KEY_TBL,  [set, public, named_table, {keypos, #router_key.key},     WC]),
    ets:new(?TAG_TBL,  [bag, public, named_table, {keypos, #meta_tag.tag},       WC]),
    ets:new(?CNT_TBL,  [set, public, named_table, {keypos, 1}]),
    ets:insert(?CNT_TBL, {inst, 0}),
    ets:insert(?CNT_TBL, {intr, 0}),
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
add_instance(_StoreArgs, Instance = #instance{name = Name, group = Group, state = State = #inst_state{}})->
    InstId = ets:update_counter(?CNT_TBL, inst, 1),
    ResolvedGroup = if
        Group =:= new     -> InstId;
        is_integer(Group) -> Group
    end,
    case Name =:= undefined orelse ets:insert_new(?NAME_TBL, #inst_name{name = Name, inst_id = InstId}) of
        true ->
            true = ets:insert(?INST_TBL, Instance#instance{
                id = InstId,
                name = Name,
                group = ResolvedGroup,
                transitions = undefined,
                state = State#inst_state{inst_id = InstId}
            }),
            {ok, InstId};
        false ->
            {error, bad_name}
    end.


%%
%%  Add a transition for an existing instance.
%%
add_transition(_StoreArgs, Transition, Messages) ->
    #transition{
        inst_id      = InstId,
        number       = TrnNr,
        attr_actions = AttrActions,
        inst_status  = Status
    } = Transition,
    true = is_list(AttrActions),
    [Instance = #instance{status = OldStatus}] = ets:lookup(?INST_TBL, InstId),
    OldTerminated = eproc_store:is_instance_terminated(OldStatus),
    NewTerminated = eproc_store:is_instance_terminated(Status),
    Action = case {OldTerminated, NewTerminated, OldStatus, Transition} of
        {false, false, suspended, #transition{inst_status = running, interrupts = undefined}} ->
            ok;
        {false, false, running, #transition{inst_status = running, interrupts = undefined}} ->
            ok;
        {false, false, running, #transition{inst_status = suspended, interrupts = [Interrupt]}} ->
            #interrupt{reason = Reason} = Interrupt,
            ok = write_instance_suspended(InstId, Reason);
        {false, false, resuming, #transition{inst_status = running, interrupts = undefined}} ->
            ok = write_instance_resumed(InstId, TrnNr);
        {false, true, _, #transition{interrupts = undefined}} ->
            ok = write_instance_terminated(Instance, Status, normal);
        {true, _, _, _} ->
            {error, terminated}
    end,
    case Action of
        ok ->
            ok = handle_attr_actions(Instance, Transition, Messages),
            true = ets:insert(?TRN_TBL, Transition#transition{interrupts = undefined}),
            [ true = ets:insert(?MSG_TBL, Message) || Message <- Messages],
            {ok, InstId, TrnNr};
        {error, ErrReason} ->
            {error, ErrReason}
    end.


%%
%%  Mark instance as killed.
%%
set_instance_killed(_StoreArgs, FsmRef, UserAction) ->
    case read_instance(FsmRef, header) of
        {error, Reason} ->
            {error, Reason};
        {ok, Instance = #instance{id = InstId, status = Status}} ->
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
    case read_instance(FsmRef, current) of
        {error, FailReason} ->
            {error, FailReason};
        {ok, #instance{id = InstId, status = Status}} ->
            case {eproc_store:is_instance_terminated(Status), Status} of
                {true, _} ->
                    {error, terminated};
                {false, suspended} ->
                    {ok, InstId};
                {false, running} ->
                    ok = write_instance_suspended(InstId, Reason),
                    {ok, InstId}
            end
    end.


%%
%%  Mark instance as resuming after it was suspended.
%%
set_instance_resuming(_StoreArgs, FsmRef, StateAction, UserAction) ->
    case read_instance(FsmRef, current) of
        {error, FailReason} ->
            {error, FailReason};
        {ok, Instance = #instance{id = InstId, status = Status, start_spec = StartSpec}} ->
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
    case write_instance_resumed(InstId, TrnNr) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
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
        (#instance{id = InstId, group = Group, start_spec = StartSpec, status = running}, Filtered) ->
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
%%
%%
get_instance(_StoreArgs, FsmRef, Query) ->
    read_instance(FsmRef, Query).


%%
%%
%%
get_transition(_StoreArgs, FsmRef, TrnNr, all) ->
    ResolveMsgRefs = fun
        (MsgRef = #msg_ref{cid = {I, T, M, sent}, peer = {inst, undefined}}) ->
            case ets:lookup(?MSG_TBL, {I, T, M, recv}) of
                [] ->
                    MsgRef;
                [#message{receiver = NewPeer}] ->
                    MsgRef#msg_ref{peer = NewPeer}
            end;
        (MsgRef) ->
            MsgRef
    end,
    case resolve_inst_id(FsmRef) of
        {ok, InstId} ->
            case ets:match_object(?TRN_TBL, #transition{inst_id = InstId, number = TrnNr, _ = '_'}) of
                [] ->
                    {error, not_found};
                [Transition = #transition{trn_messages = TrnMessages}] ->
                    NewTrnMessages = lists:map(ResolveMsgRefs, TrnMessages),
                    {ok, Transition#transition{trn_messages = NewTrnMessages}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%
%%
get_message(_StoreArgs, MsgId, all) ->
    {InstId, TrnNr, MsgNr} = case MsgId of
        {I, T, M}    -> {I, T, M};
        {I, T, M, _} -> {I, T, M}
    end,
    case ets:lookup(?MSG_TBL, {InstId, TrnNr, MsgNr, recv}) of
        [] ->
            case ets:lookup(?MSG_TBL, {InstId, TrnNr, MsgNr, sent}) of
                [] ->
                    {error, not_found};
                [Message] ->
                    {ok, Message#message{id = {I, T, M}}}
            end;
        [Message] ->
            {ok, Message#message{id = {I, T, M}}}
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
    {ok, Instance#instance{state = undefined, transitions = undefined}};

read_instance_data(Instance, current) ->
    {ok, CurrentState} = read_state(Instance, current),
    {ok, Instance#instance{state = CurrentState, transitions = undefined}}.


%%
%%  Read instance state according to the query.
%%
read_state(#instance{id = InstId, state = InstState}, current) ->
    Transitions = ets:lookup(?TRN_TBL, InstId),
    SortedTrns = lists:keysort(#transition.number, Transitions),
    CurrentState = lists:foldl(fun eproc_store:apply_transition/2, InstState, SortedTrns),
    case read_active_interrupt(InstId) of
        {ok, Interrupt} ->
            {ok, CurrentState#inst_state{interrupt = Interrupt}};
        {error, not_found} ->
            {ok, CurrentState#inst_state{interrupt = undefined}}
    end.


%%
%%  Reads currently active instance interrupt record.
%%
read_active_interrupt(InstId) ->
    Pattern = #interrupt{
        inst_id = InstId,
        status = active,
        _ = '_'
    },
    case ets:match_object(?INTR_TBL, Pattern) of
        [Interrupt] -> {ok, Interrupt};
        [] -> {error, not_found}
    end.


%%
%%  Mark instance as terminated.
%%
write_instance_terminated(#instance{id = InstId, name = Name}, Status, Reason) ->
    true = ets:update_element(?INST_TBL, InstId, [
        {#instance.status,      Status},
        {#instance.terminated,  os:timestamp()},
        {#instance.term_reason, Reason}
    ]),
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
write_instance_suspended(InstId, Reason) ->
    {error, not_found} = read_active_interrupt(InstId),
    true = ets:update_element(?INST_TBL, InstId, {#instance.status, suspended}),
    SuspId = ets:update_counter(?CNT_TBL, intr, 1),
    Interrupt = #interrupt{
        id          = SuspId,
        inst_id     = InstId,
        trn_nr      = undefined,
        status      = active,
        suspended   = os:timestamp(),
        reason      = Reason,
        resumes     = []
    },
    true = ets:insert(?INTR_TBL, Interrupt),
    ok.


%%
%%  Mark instance as resuming.
%%
write_instance_resuming(#instance{id = InstId}, StateAction, UserAction) ->
    {ok, Interrupt = #interrupt{resumes = Resumes}} = read_active_interrupt(InstId),
    LastResNumber = case Resumes of
        [] -> 0;
        [#resume_attempt{number = N} | _] -> N
    end,
    ResumeAttempt = case StateAction of
        unchanged ->
            #resume_attempt{
                number = LastResNumber + 1,
                upd_sname = undefined,
                upd_sdata = undefined,
                upd_script = undefined,
                resumed = UserAction
            };
        retry_last ->
            case Resumes of
                [] ->
                    #resume_attempt{
                        number = LastResNumber + 1,
                        upd_sname = undefined,
                        upd_sdata = undefined,
                        upd_script = undefined,
                        resumed = UserAction
                    };
                [#resume_attempt{upd_sname = LastSName, upd_sdata = LastSData, upd_script = LastScript} | _] ->
                    #resume_attempt{
                        number = LastResNumber + 1,
                        upd_sname = LastSName,
                        upd_sdata = LastSData,
                        upd_script = LastScript,
                        resumed = UserAction
                    }
            end;
        {set, NewStateName, NewStateData, ResumeScript} ->
            #resume_attempt{
                number = LastResNumber + 1,
                upd_sname = NewStateName,
                upd_sdata = NewStateData,
                upd_script = ResumeScript,
                resumed = UserAction
            }
    end,
    NewInterrupt = Interrupt#interrupt{
        resumes = [ResumeAttempt | Resumes]
    },
    true = ets:update_element(?INST_TBL, InstId, {#instance.status, resuming}),
    true = ets:delete_object(?INTR_TBL, Interrupt),
    true = ets:insert(?INTR_TBL, NewInterrupt),
    ok.


%%
%%  Mark instance as running (resumed).
%%
write_instance_resumed(InstId, TrnNr) ->
    case read_active_interrupt(InstId) of
        {ok, Interrupt} ->
            NewInterrupt = Interrupt#interrupt{
                trn_nr = TrnNr,
                status = closed
            },
            true = ets:delete_object(?INTR_TBL, Interrupt),
            true = ets:insert(?INTR_TBL, NewInterrupt);
        {error, not_found} ->
            ok
    end,
    true = ets:update_element(?INST_TBL, InstId, {#instance.status, running}),
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
    #attr_action{attr_id = AttrId, action = Action} = AttrAction,
    #instance{id = InstId} = Instance,
    case Action of
        {create, _Name, _Scope, {data, Key, _SyncRef}} ->
            true = ets:insert(?KEY_TBL, #router_key{key = Key, inst_id = InstId, attr_id = AttrId}),
            ok;
        {remove, _Reason} ->
            true = ets:match_delete(?KEY_TBL, #router_key{attr_id = AttrId, _ = '_'}),
            ok
    end.

%%
%%
%%
handle_attr_custom_router_task({key_sync, Key, InstId, Uniq}) ->
    AddKeyFun = fun () ->
        SyncRef = {'eproc_router$key_sync', node(), erlang:now()},
        true = ets:insert_new(?KEY_TBL, #router_key{key = Key, inst_id = InstId, attr_id = SyncRef}),
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
    #attr_action{attr_id = AttrId, action = Action} = AttrAction,
    #instance{id = InstId} = Instance,
    case Action of
        {create, _Name, _Scope, {data, Tag, Type}} ->
            true = ets:insert(?TAG_TBL, #meta_tag{tag = Tag, type = Type, inst_id = InstId, attr_id = AttrId}),
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


