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
    ets:new('eproc_store_ets$inst', [set, public, named_table, {keypos, #instance.id}]),
    ets:new('eproc_store_ets$cntr', [set, public, named_table, {keypos, 1}]),
    ets:insert('eproc_store_ets$cntr', {inst, 0}),
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
%%
%%
add_instance(_StoreArgs, Instance = #instance{name = Name, group = Group}) ->
    InstId = ets:update_counter('eproc_store_ets$cntr', inst, 1),
    ResolvedGroup = if
        Group =:= new     -> InstId;
        is_integer(Group) -> Group
    end,
    ResolvedName = case Name of
        undefined -> undefined;
        _         -> Name
    end,
    true = ets:insert('eproc_store_ets$inst', Instance#instance{
        id = InstId,
        name = ResolvedName,
        group = ResolvedGroup,
        transitions = undefined
    }),
    {ok, InstId}.


%%
%%
%%
add_transition(_StoreArgs, _Transition, _Messages) ->
    {error, not_implemented}.   % TODO


%%
%%  Loads instance data for runtime.
%%
load_instance(_StoreArgs, {inst, InstId}) ->
    case ets:lookup('eproc_store_ets$inst', InstId) of
        [] ->
            {error, not_found};
        [Instance] ->
            Transitions = [],   % TODO
            LoadedInstance = Instance#instance{
                transitions = Transitions
            },
            {ok, LoadedInstance}
    end;

load_instance(_StoreArgs, {name, undefined}) ->
    {error, not_found};

load_instance(_StoreArgs, {name, Name}) ->
    case ets:match_object('eproc_store_ets$inst', #instance{name = Name, _ = '_'}) of
        [] ->
            {error, not_found};
        [Instance] ->
            Transitions = [],   % TODO
            LoadedInstance = Instance#instance{
                transitions = Transitions
            },
            {ok, LoadedInstance}
    end.


%%
%%
%%
load_running(_StoreArgs, PartitionPred) ->
    {ok, []}.   % TODO: Implement.


%%
%%
%%
get_instance(_StoreArgs, {inst, InstId}, _Query) ->
    case ets:lookup('eproc_store_ets$inst', InstId) of
        [] ->
            {error, not_found};
        [Instance] ->
            % TODO: how about transitions ?
            % Transitions = [],
            % LoadedInstance = Instance#instance{
                % transitions = Transitions
            % },
            {ok, Instance}
    end;

get_instance(_StoreArgs, {name, _Name}, _Query) ->
    {error, not_implemented}.   % TODO



%% =============================================================================
%%  Internal functions.
%% =============================================================================


