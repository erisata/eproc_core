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
-export([supervisor_child_specs/1, add_instance/2, add_transition/3, load_instance/2, load_running/2, get_instance/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").

-define(INST_TBL, 'eproc_store_ets$instance').
-define(NAME_TBL, 'eproc_store_ets$inst_name').
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
    ets:new(?TRN_TBL,  [bag, public, named_table, {keypos, #transition.inst_id}, WC]),
    ets:new(?MSG_TBL,  [set, public, named_table, {keypos, #message.id},         WC]),
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
            {error, name_not_uniq}
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
    OldStatus = ets:lookup_element(?INST_TBL, InstId, #instance.status),

    true = ets:insert(?TRN_TBL, Transition),
    [ true = ets:insert(?MSG_TBL, Message) || Message <- Messages],

    true = case Status =:= OldStatus of
        true  -> true;
        false -> ets:update_element(?INST_TBL, InstId, {#instance.status, Status})
    end,
    {ok, TrnNr}.


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
%%
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


