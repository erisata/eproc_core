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
%%
-module(eproc_store_ets).
-behaviour(eproc_store).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1]).
-export([
    supervisor_child_specs/1,
    get_instance/3
]).
-export([
    add_instance/2,
    add_transition/3,
    set_instance_killed/3,
    set_instance_suspended/3,
    load_instance/2,
    load_running/2
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").

-define(INST_TBL, 'eproc_store_ets$instance').
-define(NAME_TBL, 'eproc_store_ets$inst_name').
-define(SUSP_TBL, 'eproc_store_ets$inst_susp').
-define(TRN_TBL,  'eproc_store_ets$transition').
-define(MSG_TBL,  'eproc_store_ets$message').
-define(CNT_TBL,  'eproc_store_ets$counter').

-record(inst_name, {
    name    :: inst_name(),
    inst_id :: inst_id()
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
    ets:new(?SUSP_TBL, [bag, public, named_table, {keypos, #inst_susp.inst_id},  WC]),
    ets:new(?TRN_TBL,  [bag, public, named_table, {keypos, #transition.inst_id}, WC]),
    ets:new(?MSG_TBL,  [set, public, named_table, {keypos, #message.id},         WC]),
    ets:new(?CNT_TBL,  [set, public, named_table, {keypos, 1}]),
    ets:insert(?CNT_TBL, {inst, 0}),
    ets:insert(?CNT_TBL, {susp, 0}),
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
%%  Returns supervisor child specifications for starting the registry.
%%
supervisor_child_specs(_StoreArgs) ->
    Mod = ?MODULE,
    Spec = {Mod, {Mod, start_link, [{local, Mod}]}, permanent, 10000, worker, [Mod]},
    {ok, [Spec]}.


%%
%%  Add new instance to the store.
%%
add_instance(_StoreArgs, Instance = #instance{name = Name, group = Group}) ->
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
                transitions = undefined
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
        attrs_active = undefined,
        inst_status  = Status,
        inst_suspend = undefined
    } = Transition,
    true = is_list(AttrActions),
    Instance = #instance{status = OldStatus} = ets:lookup(?INST_TBL, InstId),

    case {is_instance_terminated(OldStatus), is_instance_terminated(Status)} of
        {false, false} ->
            ok;
        {false, true} ->
            ok = write_instance_terminated(Instance, Status, normal)
    end,

    true = ets:insert(?TRN_TBL, Transition),
    [ true = ets:insert(?MSG_TBL, Message) || Message <- Messages],
    {ok, InstId, TrnNr}.


%%
%%  Mark instance as killed.
%%
set_instance_killed(_StoreArgs, FsmRef, UserAction) ->
    case read_instance(FsmRef, header) of
        {error, Reason} ->
            {error, Reason};
        {ok, Instance = #instance{id = InstId, status = Status}} ->
            case is_instance_terminated(Status) of
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
        {error, Reason} ->
            {error, Reason};
        {ok, Instance = #instance{id = InstId, status = Status}} ->
            case {is_instance_terminated(Status), Status} of
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
%%
%%
get_instance(_StoreArgs, FsmRef, Query) ->
    read_instance(FsmRef, Query).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Reads instance record.
%%
read_instance({inst, InstId}, Query) ->
    case ets:lookup(?INST_TBL, InstId) of
        [] ->
            {error, not_found};
        [Instance] ->
            read_instance_data(Instance, Query)
    end;

read_instance({name, Name}, Query) ->
    case ets:lookup(?NAME_TBL, Name) of
        [] ->
            {error, not_found};
        [#inst_name{inst_id = InstId}] ->
            read_instance({inst, InstId}, Query)
    end.


%%
%%  Reads instance related data according to query.
%%
read_instance_data(Instance, header) ->
    {ok, Instance#instance{transitions = undefined}};

read_instance_data(Instance, current) ->
    Transitions = read_transitions(Instance, last),
    {ok, Instance#instance{transitions = Transitions}}.


%%
%%  Read instance transitions according to the query.
%%
read_transitions(#instance{id = InstId}, last) ->
    case ets:lookup(?TRN_TBL, InstId) of
        [] ->
            [];
        Transitions ->
            SortedTrns = lists:keysort(#transition.number, Transitions),
            case lists:foldl(fun aggregate_attrs/2, undefined, SortedTrns) of
                undefined -> [];
                LastTrn   -> [LastTrn]
            end
    end.


%%
%%  Mark instance as terminated.
%%
write_instance_terminated(#instance{id = InstId, name = Name}, Status, Reason) ->
    true = ets:update_element(?INST_TBL, InstId, [
        {#instance.status,      Status},
        {#instance.terminated,  erlang:now()},
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
write_instance_suspended(#instance{id = InstId, transitions = Transitions}, Reason) ->
    true = ets:update_element(?INST_TBL, InstId, {#instance.status, suspended}),
    TrnNr = case Transitions of
        [] -> 0;
        [#transition{number = N}] -> N
    end,
    SuspId = ets:update_counter(?CNT_TBL, susp, 1),
    InstSuspension = #inst_susp{
        id          = SuspId,
        inst_id     = InstId,
        trn_nr      = TrnNr,
        suspended   = erlang:now(),
        reason      = Reason,
        updated     = undefined,
        upd_sname   = undefined,
        upd_sdata   = undefined,
        upd_attrs   = undefined,
        resumed     = undefined
    },
    true = ets:insert_new(?SUSP_TBL, InstSuspension),
    ok.


%%
%%  Replay all attribute actions, from all transitions.
%%  TODO: Move this function to `eproc_store`.
%%
aggregate_attrs(Transition, undefined) ->
    #transition{inst_id = InstId, number = TrnNr, attr_actions = AttrActions} = Transition,
    Transition#transition{attrs_active = apply_attr_action(AttrActions, [], InstId, TrnNr)};

aggregate_attrs(Transition, #transition{attrs_active = AttrsActive}) ->
    #transition{inst_id = InstId, number = TrnNr, attr_actions = AttrActions} = Transition,
    Transition#transition{attrs_active = apply_attr_action(AttrActions, AttrsActive, InstId, TrnNr)}.


%%
%%  Replays single attribute action.
%%  Returns a list of active attributes after applying the provided attribute action.
%%  TODO: Move this function to `eproc_store`.
%%
apply_attr_action(#attr_action{module = Module, attr_id = AttrId, action = Action}, Attrs, InstId, TrnNr) ->
    case Action of
        {create, Name, Scope, Data} ->
            NewAttr = #attribute{
                inst_id = InstId,
                attr_id = AttrId,
                module = Module,
                name = Name,
                scope = Scope,
                data = Data,
                from = TrnNr,
                upds = [],
                till = undefined,
                reason = undefined
            },
            [NewAttr | Attrs];
        {update, NewScope, NewData} ->
            Attr = #attribute{upds = Upds} = lists:keyfind(AttrId, #attribute.attr_id, Attrs),
            NewAttr = Attr#attribute{
                scope = NewScope,
                data = NewData,
                upds = [TrnNr | Upds]
            },
            lists:keyreplace(AttrId, #attribute.attr_id, Attrs, NewAttr);
        {remove, _Reason} ->
            lists:keydelete(AttrId, #attribute.attr_id, Attrs)
    end.


%%
%%  Checks if instance is terminated by status.
%%
is_instance_terminated(running) -> false;
is_instance_terminated(suspend) -> false;
is_instance_terminated(done)    -> true;
is_instance_terminated(failed)  -> true;
is_instance_terminated(killed)  -> true.


